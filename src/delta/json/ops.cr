# src/delta/json/ops.cr
module Delta::JSON
  module Ops
    record Replace, value : ::JSON::Any do
      def path : Path
        Path.new
      end

      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "r"
          @value.to_json(json)
        end
      end
    end

    record Set, path : Path, value : ::JSON::Any do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "s"
          @path.to_json(json)
          @value.to_json(json)
        end
      end
    end

    record Delete, path : Path do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "d"
          @path.to_json(json)
        end
      end
    end

    record Append, path : Path, text : String do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "a"
          @path.to_json(json)
          json.string @text
        end
      end
    end

    record Trim, path : Path, count : Int32 do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "t"
          @path.to_json(json)
          json.number @count
        end
      end
    end

    record Splice, path : Path, index : Int32, remove : Int32, items : Array(::JSON::Any) do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "p"
          @path.to_json(json)
          json.number @index
          json.number @remove
          @items.to_json(json)
        end
      end
    end

    record Move, path : Path, permutation : Array(Int32) do
      def to_json(json : ::JSON::Builder) : Nil
        json.array do
          json.string "m"
          @path.to_json(json)
          @permutation.to_json(json)
        end
      end
    end
  end

  alias Op = Ops::Replace | Ops::Set | Ops::Delete | Ops::Append | Ops::Trim | Ops::Splice | Ops::Move

  def self.leaf?(op : Op) : Bool
    case op
    when Ops::Append
      true
    when Ops::Set
      !container?(op.value)
    else
      false
    end
  end

  def self.parse_ops(source : String) : Array(Op)
    parse_ops(::JSON.parse(source))
  end

  def self.parse_ops(source : ::JSON::Any) : Array(Op)
    tuples = source.as_a? || raise Errors::InvalidOp.new("batch must be an array")
    tuples.map { |tuple| parse_op(tuple) }
  end

  def self.parse_op(source : ::JSON::Any) : Op
    tuple = source.as_a? || raise Errors::InvalidOp.new("op must be an array")
    code = tuple[0]?.try(&.as_s?) || raise Errors::InvalidOp.new("op must start with its code")
    if code == "r"
      expect_arity(tuple, 2)
      return Ops::Replace.new(tuple[1])
    end
    build_op(code, parse_path(tuple[1]? || raise Errors::InvalidOp.new("op '#{code}' needs a path")), tuple)
  end

  def self.parse_path(source : ::JSON::Any) : Path
    segments = source.as_a? || raise Errors::InvalidOp.new("path must be an array")
    segments.map { |segment| parse_segment(segment) }
  end

  def self.parse_segment(source : ::JSON::Any) : Segment
    case raw = source.raw
    when String
      raw
    when Int64
      raise Errors::InvalidOp.new("index out of range: #{raw}") unless 0 <= raw <= Int32::MAX
      raw.to_i32
    else
      raise Errors::InvalidOp.new("path segment must be a string or an index")
    end
  end

  def self.build_op(code : String, path : Path, tuple : Array(::JSON::Any)) : Op
    case code
    when "s"
      expect_arity(tuple, 3)
      Ops::Set.new(path, tuple[2])
    when "d"
      expect_arity(tuple, 2)
      Ops::Delete.new(path)
    when "a"
      expect_arity(tuple, 3)
      Ops::Append.new(path, tuple[2].as_s? || raise Errors::InvalidOp.new("append text must be a string"))
    when "t"
      expect_arity(tuple, 3)
      Ops::Trim.new(path, count(tuple[2]))
    when "p"
      expect_arity(tuple, 5)
      items = tuple[4].as_a? || raise Errors::InvalidOp.new("splice items must be an array")
      Ops::Splice.new(path, count(tuple[2]), count(tuple[3]), items)
    when "m"
      expect_arity(tuple, 3)
      permutation = tuple[2].as_a? || raise Errors::InvalidOp.new("permutation must be an array")
      Ops::Move.new(path, permutation.map { |entry| count(entry) })
    else
      raise Errors::InvalidOp.new("unknown op code: #{code}")
    end
  end

  protected def self.expect_arity(tuple : Array(::JSON::Any), size : Int32) : Nil
    raise Errors::InvalidOp.new("op '#{tuple[0]}' expects #{size} elements, got #{tuple.size}") unless tuple.size == size
  end

  protected def self.count(source : ::JSON::Any) : Int32
    value = source.as_i64? || raise Errors::InvalidOp.new("expected a non-negative integer")
    raise Errors::InvalidOp.new("expected a non-negative integer") unless 0 <= value <= Int32::MAX
    value.to_i32
  end
end
