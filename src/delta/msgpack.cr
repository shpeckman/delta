# src/delta/msgpack.cr
require "msgpack"
require "sync/mutex"
require "sync/condition_variable"
require "./tree"

module Delta::Msgpack
  alias Segment = MessagePack::Type
  alias Path = Array(MessagePack::Type)

  module Errors
    class Error < Exception
    end

    class InvalidPath < Error
    end

    class InvalidValue < Error
    end

    class InvalidOp < Error
    end

    class Stale < Error
    end

    class Settled < Error
    end

    class Rejected < Error
    end

    class Closed < Error
    end
  end

  def self.format(path : Path) : String
    return "/" if path.empty?
    String.build do |io|
      path.each do |segment|
        io << '/'
        io << segment.to_s
      end
    end
  end

  def self.any(value : MessagePack::Type) : MessagePack::Type
    copy(value)
  end

  def self.any(value : MessagePack::Any) : MessagePack::Type
    copy(value.raw)
  end

  def self.any(value : String) : MessagePack::Type
    value
  end

  def self.any(value : Bool) : MessagePack::Type
    value
  end

  def self.any(value : Nil) : MessagePack::Type
    nil
  end

  def self.any(value : Int) : MessagePack::Type
    value.to_i64
  end

  def self.any(value : Float) : MessagePack::Type
    value.to_f64
  end

  def self.nil_value : MessagePack::Type
    nil
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

  def self.pack_ops(ops : Array(Op)) : Bytes
    MessagePack.pack(ops.map { |op| op_tuple(op) })
  end

  def self.unpack_ops(bytes : Bytes) : Array(Op)
    unpack_ops(MessagePack.unpack(bytes).raw)
  end

  def self.unpack_ops(any : MessagePack::Any) : Array(Op)
    unpack_ops(any.raw)
  end

  def self.unpack_ops(value : MessagePack::Type) : Array(Op)
    tuples = value.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("batch must be an array")
    tuples.map { |tuple| unpack_op(tuple) }
  end

  def self.unpack_op(value : MessagePack::Type) : Op
    tuple = value.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("op must be an array")
    code = tuple[0]?.try(&.as?(String)) || raise Errors::InvalidOp.new("op must start with its code")
    if code == "r"
      expect_arity(tuple, 2)
      return Ops::Replace.new(tuple[1])
    end
    build_op(code, unpack_path(tuple[1]? || raise Errors::InvalidOp.new("op '#{code}' needs a path")), tuple)
  end

  protected def self.op_tuple(op : Op) : MessagePack::Type
    case op
    in Ops::Replace
      ["r", op.value] of MessagePack::Type
    in Ops::Set
      ["s", op.path, op.value] of MessagePack::Type
    in Ops::Delete
      ["d", op.path] of MessagePack::Type
    in Ops::Append
      ["a", op.path, op.text] of MessagePack::Type
    in Ops::Trim
      ["t", op.path, op.count] of MessagePack::Type
    in Ops::Splice
      ["p", op.path, op.index, op.remove, op.items] of MessagePack::Type
    in Ops::Move
      ["m", op.path, op.permutation.map { |entry| entry.as(MessagePack::Type) }] of MessagePack::Type
    end
  end

  protected def self.unpack_path(value : MessagePack::Type) : Path
    value.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("path must be an array")
  end

  def self.build_op(code : String, path : Path, tuple : Array(MessagePack::Type)) : Op
    case code
    when "s"
      expect_arity(tuple, 3)
      Ops::Set.new(path, tuple[2])
    when "d"
      expect_arity(tuple, 2)
      Ops::Delete.new(path)
    when "a"
      expect_arity(tuple, 3)
      Ops::Append.new(path, tuple[2].as?(String) || raise Errors::InvalidOp.new("append text must be a string"))
    when "t"
      expect_arity(tuple, 3)
      Ops::Trim.new(path, count(tuple[2]))
    when "p"
      expect_arity(tuple, 5)
      items = tuple[4].as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("splice items must be an array")
      Ops::Splice.new(path, count(tuple[2]), count(tuple[3]), items)
    when "m"
      expect_arity(tuple, 3)
      permutation = tuple[2].as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("permutation must be an array")
      Ops::Move.new(path, permutation.map { |entry| count(entry) })
    else
      raise Errors::InvalidOp.new("unknown op code: #{code}")
    end
  end

  protected def self.expect_arity(tuple : Array(MessagePack::Type), size : Int32) : Nil
    raise Errors::InvalidOp.new("op '#{tuple[0]}' expects #{size} elements, got #{tuple.size}") unless tuple.size == size
  end

  protected def self.count(value : MessagePack::Type) : Int32
    case value
    when Int8, Int16, Int32, Int64
      number = value.to_i64
      raise Errors::InvalidOp.new("expected a non-negative integer") unless 0 <= number <= Int32::MAX
      number.to_i32
    when UInt8, UInt16, UInt32, UInt64
      number = value.to_u64
      raise Errors::InvalidOp.new("expected a non-negative integer") unless number <= Int32::MAX
      number.to_i32
    else
      raise Errors::InvalidOp.new("expected a non-negative integer")
    end
  end

  module Wire
    class Encoder
      def initialize
        @ids = Hash(Path, Int32).new
        @next = 0
      end

      def encode(ops : Array(Op)) : Bytes
        MessagePack.pack(ops.map { |op| encode_op(op) })
      end

      def reset : Nil
        @ids.clear
        @next = 0
      end

      private def encode_op(op : Op) : MessagePack::Type
        if op.is_a?(Ops::Replace)
          reset
          return ["r", op.value] of MessagePack::Type
        end
        case op
        in Ops::Replace
          ["r", op.value] of MessagePack::Type
        in Ops::Set
          ["s", path(op.path), op.value] of MessagePack::Type
        in Ops::Delete
          ["d", path(op.path)] of MessagePack::Type
        in Ops::Append
          ["a", path(op.path), op.text] of MessagePack::Type
        in Ops::Trim
          ["t", path(op.path), op.count] of MessagePack::Type
        in Ops::Splice
          ["p", path(op.path), op.index, op.remove, op.items] of MessagePack::Type
        in Ops::Move
          ["m", path(op.path), op.permutation.map { |entry| entry.as(MessagePack::Type) }] of MessagePack::Type
        end
      end

      private def path(path : Path) : MessagePack::Type
        if id = @ids[path]?
          return id.as(MessagePack::Type)
        end
        id = @next
        @next += 1
        @ids[path] = id
        [id.as(MessagePack::Type), path] of MessagePack::Type
      end
    end

    class Decoder
      def initialize
        @paths = Hash(Int32, Path).new
      end

      def decode(bytes : Bytes) : Array(Op)
        decode(MessagePack.unpack(bytes).raw)
      end

      def decode(value : MessagePack::Type) : Array(Op)
        tuples = value.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("wire batch must be an array")
        tuples.map { |tuple| decode_op(tuple) }
      end

      def reset : Nil
        @paths.clear
      end

      private def decode_op(value : MessagePack::Type) : Op
        source = value.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("wire op must be an array")
        code = source[0]?.try(&.as?(String)) || raise Errors::InvalidOp.new("wire op must start with its code")
        if code == "r"
          reset
          return Ops::Replace.new(source[1])
        end
        reference = source[1]? || raise Errors::InvalidOp.new("wire op '#{code}' needs a path")
        build_op(code, resolve(reference), source)
      end

      private def resolve(reference : MessagePack::Type) : Path
        if id = integer(reference)
          return @paths[id]? || raise Errors::InvalidOp.new("unknown path id #{id}")
        end
        entries = reference.as?(Array(MessagePack::Type)) || raise Errors::InvalidOp.new("wire path must be an id or a definition")
        id = entries[0]?.try { |entry| integer(entry) } || raise Errors::InvalidOp.new("wire path definition must start with its id")
        path = entries[1..]
        @paths[id] = path
        path
      end

      private def integer(value : MessagePack::Type) : Int32?
        case value
        when Int8, Int16, Int32, Int64
          number = value.to_i64
          0 <= number <= Int32::MAX ? number.to_i32 : nil
        when UInt8, UInt16, UInt32, UInt64
          number = value.to_u64
          number <= Int32::MAX ? number.to_i32 : nil
        else
          nil
        end
      end
    end
  end
end
