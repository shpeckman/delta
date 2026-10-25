# src/delta/msgpack.cr
require "msgpack"
require "./tree"

module Delta::Msgpack
  alias Segment = MessagePack::Type | Int32
  alias Path = Array(Segment)

  module Errors
    class Error < Exception
    end

    class InvalidPath < Error
    end

    class InvalidValue < Error
    end

    class InvalidOp < Error
    end
  end

  def self.format(path : Path) : String
    return "/" if path.empty?
    String.build do |io|
      path.each do |segment|
        io << '/'
        io << segment.inspect
      end
    end
  end

  def self.any(value : MessagePack::Any) : MessagePack::Type
    value.raw
  end

  def self.copy(value : MessagePack::Type) : MessagePack::Type
    case value
    when Hash(MessagePack::Type, MessagePack::Type)
      hash = Hash(MessagePack::Type, MessagePack::Type).new(initial_capacity: value.size)
      value.each { |key, child| hash[key] = copy(child) }
      hash
    when Array(MessagePack::Type)
      value.map { |child| copy(child) }
    else
      value
    end
  end

  def self.container?(value : MessagePack::Type) : Bool
    value.is_a?(Hash(MessagePack::Type, MessagePack::Type)) || value.is_a?(Array(MessagePack::Type))
  end

  def self.identical?(left : MessagePack::Type, right : MessagePack::Type) : Bool
    case left
    when Hash(MessagePack::Type, MessagePack::Type)
      right.is_a?(Hash(MessagePack::Type, MessagePack::Type)) && left.same?(right)
    when Array(MessagePack::Type)
      right.is_a?(Array(MessagePack::Type)) && left.same?(right)
    else
      false
    end
  end

  def self.hash?(value : MessagePack::Type) : Hash(MessagePack::Type, MessagePack::Type)?
    value.as?(Hash(MessagePack::Type, MessagePack::Type))
  end

  def self.array?(value : MessagePack::Type) : Array(MessagePack::Type)?
    value.as?(Array(MessagePack::Type))
  end

  def self.string?(value : MessagePack::Type) : String?
    value.as?(String)
  end

  def self.wrap_hash(hash : Hash(MessagePack::Type, MessagePack::Type)) : MessagePack::Type
    hash
  end

  def self.wrap_array(array : Array(MessagePack::Type)) : MessagePack::Type
    array
  end

  def self.wrap_string(text : String) : MessagePack::Type
    text
  end

  Tree.define(MessagePack::Type, MessagePack::Type, Delta::Msgpack)
end
