# src/delta/json/wire.cr
module Delta::JSON::Wire
  class Encoder
    def initialize
      @ids = Hash(Path, Int32).new
      @next = 0
    end

    def encode(ops : Array(Op)) : String
      ::JSON.build { |json| encode(ops, json) }
    end

    def encode(ops : Array(Op), json : ::JSON::Builder) : Nil
      json.array do
        ops.each { |op| encode_op(op, json) }
      end
    end

    def reset : Nil
      @ids.clear
      @next = 0
    end

    private def encode_op(op : Op, json : ::JSON::Builder) : Nil
      if op.is_a?(Ops::Replace)
        reset
        op.to_json(json)
        return
      end
      json.array do
        case op
        in Ops::Replace
        in Ops::Set
          json.string "s"
          path(op.path, json)
          op.value.to_json(json)
        in Ops::Delete
          json.string "d"
          path(op.path, json)
        in Ops::Append
          json.string "a"
          path(op.path, json)
          json.string op.text
        in Ops::Trim
          json.string "t"
          path(op.path, json)
          json.number op.count
        in Ops::Splice
          json.string "p"
          path(op.path, json)
          json.number op.index
          json.number op.remove
          op.items.to_json(json)
        in Ops::Move
          json.string "m"
          path(op.path, json)
          op.permutation.to_json(json)
        end
      end
    end

    private def path(path : Path, json : ::JSON::Builder) : Nil
      if id = @ids[path]?
        json.number id
        return
      end
      id = @next
      @next += 1
      @ids[path] = id
      json.array do
        json.number id
        path.each do |segment|
          case segment
          in String
            json.string segment
          in Int32
            json.number segment
          end
        end
      end
    end
  end

  class Decoder
    def initialize
      @paths = Hash(Int32, Path).new
    end

    def decode(frame : String) : Array(Op)
      decode(::JSON.parse(frame))
    end

    def decode(frame : ::JSON::Any) : Array(Op)
      tuples = frame.as_a? || raise Errors::InvalidOp.new("wire batch must be an array")
      tuples.map { |tuple| decode_op(tuple) }
    end

    def reset : Nil
      @paths.clear
    end

    private def decode_op(source : ::JSON::Any) : Op
      tuple = source.as_a? || raise Errors::InvalidOp.new("wire op must be an array")
      code = tuple[0]?.try(&.as_s?) || raise Errors::InvalidOp.new("wire op must start with its code")
      if code == "r"
        reset
        return JSON.parse_op(source)
      end
      reference = tuple[1]? || raise Errors::InvalidOp.new("wire op '#{code}' needs a path")
      JSON.build_op(code, resolve(reference), tuple)
    end

    private def resolve(reference : ::JSON::Any) : Path
      if id = reference.as_i64?
        return @paths[id.to_i32]? || raise Errors::InvalidOp.new("unknown path id #{id}")
      end
      entries = reference.as_a? || raise Errors::InvalidOp.new("wire path must be an id or a definition")
      id = entries[0]?.try(&.as_i64?) || raise Errors::InvalidOp.new("wire path definition must start with its id")
      path = entries[1..].map { |segment| JSON.parse_segment(segment) }
      @paths[id.to_i32] = path
      path
    end
  end
end
