#!/usr/bin/env ruby
#
# = plist
#
# Copyright 2006-2010 Ben Bleything and Patrick May
# Distributed under the MIT License
#

module Plist ; end

# === Create a plist
# You can dump an object to a plist in one of two ways:
#
# * <tt>Plist::Emit.dump(obj)</tt>
# * <tt>obj.to_plist</tt>
#   * This requires that you mixin the <tt>Plist::Emit</tt> module, which is already done for +Array+ and +Hash+.
#
# The following Ruby classes are converted into native plist types:
#   Array, Bignum, Date, DateTime, Fixnum, Float, Hash, Integer, String, Symbol, Time, true, false
# * +Array+ and +Hash+ are both recursive; their elements will be converted into plist nodes inside the <array> and <dict> containers (respectively).
# * +IO+ (and its descendants) and +StringIO+ objects are read from and their contents placed in a <data> element.
# * User classes may implement +to_plist_node+ to dictate how they should be serialized; otherwise the object will be passed to <tt>Marshal.dump</tt> and the result placed in a <data> element.
#
# For detailed usage instructions, refer to USAGE[link:files/docs/USAGE.html] and the methods documented below.
module Plist::Emit
  # Helper method for injecting into classes.  Calls <tt>Plist::Emit.dump</tt> with +self+.
  def to_plist(envelope = true)
    return Plist::Emit.dump(self, envelope)
  end

  # Helper method for injecting into classes.  Calls <tt>Plist::Emit.save_plist</tt> with +self+.
  def save_plist(filename)
    Plist::Emit.save_plist(self, filename)
  end

  # The following Ruby classes are converted into native plist types:
  #   Array, Bignum, Date, DateTime, Fixnum, Float, Hash, Integer, String, Symbol, Time
  #
  # Write us (via RubyForge) if you think another class can be coerced safely into one of the expected plist classes.
  #
  # +IO+ and +StringIO+ objects are encoded and placed in <data> elements; other objects are <tt>Marshal.dump</tt>'ed unless they implement +to_plist_node+.
  #
  # The +envelope+ parameters dictates whether or not the resultant plist fragment is wrapped in the normal XML/plist header and footer.  Set it to false if you only want the fragment.
  def self.dump(obj, envelope = true)
    output = obj.to_plist_node

    output = wrap(output) if envelope

    return output
  end

  # Writes the serialized object's plist to the specified filename.
  def self.save_plist(obj, filename)
    File.open(filename, 'wb') do |f|
      f.write(obj.to_plist)
    end
  end
  
  def self.tag(type, contents = '', &block)
    out = nil

    if block_given?
      out = IndentedString.new
      out << "<#{type}>"
      out.raise_indent

      out << block.call

      out.lower_indent
      out << "</#{type}>"
    else
      out = "<#{type}>#{contents.to_s}</#{type}>\n"
    end

    return out.to_s
  end

  def self.wrap(contents)
    output = ''

    output << '<?xml version="1.0" encoding="UTF-8"?>' + "\n"
    output << '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' + "\n"
    output << '<plist version="1.0">' + "\n"

    output << contents

    output << '</plist>' + "\n"

    return output
  end
  
  private
  class IndentedString #:nodoc:
    attr_accessor :indent_string

    def initialize(str = "\t")
      @indent_string = str
      @contents = ''
      @indent_level = 0
    end

    def to_s
      return @contents
    end

    def raise_indent
      @indent_level += 1
    end

    def lower_indent
      @indent_level -= 1 if @indent_level > 0
    end

    def <<(val)
      if val.is_a? Array
        val.each do |f|
          self << f
        end
      else
        # if it's already indented, don't bother indenting further
        unless val =~ /\A#{@indent_string}/
          indent = @indent_string * @indent_level

          @contents << val.gsub(/^/, indent)
        else
          @contents << val
        end

        # it already has a newline, don't add another
        @contents << "\n" unless val =~ /\n$/
      end
    end
  end
end


module Plist::Node
  include Plist::Emit
  
  def plist_element_type
    case self
    when String, Symbol
      'string'

    when Fixnum, Bignum, Integer
      'integer'

    when Float
      'real'

    else
      raise "Don't know about this data type... something must be wrong!"
    end
  end
  
  def comment(content)
    return "<!-- #{content} -->\n"
  end
  
  def to_plist_node
    output = ''
      
    case self
    when ActiveRecord::Base
      output << self.plist_attributes.to_plist_node
    when Array
      if self.empty?
        output << "<array/>\n"
      else
        output << Plist::Emit.tag('array') {
          self.collect {|e| e.to_plist_node}
        }
      end
    when Hash
      if self.empty?
        output << "<dict/>\n"
      else
        inner_tags = []

        self.keys.sort_by{|k| k.to_s }.each do |k|
          v = self[k]
          inner_tags << Plist::Emit.tag('key', CGI::escapeHTML(k.to_s))
          inner_tags << v.to_plist_node
        end

        output << Plist::Emit.tag('dict') {
          inner_tags
        }
      end
    when true, false
      output << "<#{self}/>\n"
    when Time
      output << Plist::Emit.tag('date', self.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
    when Date # also catches DateTime
      output << Plist::Emit.tag('date', self.strftime('%Y-%m-%dT%H:%M:%SZ'))
    when String, Symbol, Fixnum, Bignum, Integer, Float
      output << Plist::Emit.tag(self.plist_element_type, CGI::escapeHTML(self.to_s))
    when IO, StringIO
      self.rewind
      contents = self.read
      # note that apple plists are wrapped at a different length then
      # what ruby's base64 wraps by default.
      # I used #encode64 instead of #b64encode (which allows a length arg)
      # because b64encode is b0rked and ignores the length arg.
      data = "\n"
      Base64::encode64(contents).gsub(/\s+/, '').scan(/.{1,68}/o) { data << $& << "\n" }
      output << Plist::Emit.tag('data', data)
    else
    
      output << comment( 'The <data> element below contains a Ruby object which has been serialized with Marshal.dump.' )
      data = "\n"
      Base64::encode64(Marshal.dump(self)).gsub(/\s+/, '').scan(/.{1,68}/o) { data << $& << "\n" }
      output << Plist::Emit.tag('data', data )
    end
      
    output
        
  end
  
  def plist_attributes
    attributes if self.is_a? ActiveRecord::Base
  end
end


class Object
  include Plist::Node
end



