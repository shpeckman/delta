# src/delta/json/pending_ops.cr
module Delta::JSON
  class PendingOps
    LIMIT = 10_000

    getter limit : Int32

    def initialize(@limit : Int32 = LIMIT)
      @ops      = Array(Op).new
      @tails    = Hash(Int32, Array(String)).new
      @leaves   = Hash(Path, Int32).new
      @overflow = false
    end

    def push(ops : Array(Op)) : Nil
      ops.each { |op| fold(op) }
    end

    def push(op : Op) : Nil
      fold(op)
    end

    def overflow? : Bool
      @overflow
    end

    def empty? : Bool
      !@overflow && @ops.empty?
    end

    def size : Int32
      @ops.size
    end

    def take(current : ::JSON::Any) : Array(Op)
      ops = @overflow ? [Ops::Replace.new(current)] of Op : materialize
      clear
      ops
    end

    def clear : Nil
      @ops      = Array(Op).new
      @tails    = Hash(Int32, Array(String)).new
      @leaves   = Hash(Path, Int32).new
      @overflow = false
    end

    private def fold(op : Op) : Nil
      if op.is_a?(Ops::Replace)
        clear
        @ops << op
        return
      end
      return if @overflow

      leaf = JSON.leaf?(op)
      if leaf && (index = @leaves[op.path]?)
        merge(index, op)
      else
        @leaves.clear unless leaf
        @ops << op
        @leaves[op.path] = @ops.size - 1 if leaf
      end

      if @ops.size > @limit
        @ops      = Array(Op).new
        @tails    = Hash(Int32, Array(String)).new
        @leaves   = Hash(Path, Int32).new
        @overflow = true
      end
    end

    private def merge(index : Int32, op : Op) : Nil
      case op
      when Ops::Append
        previous = @ops[index]
        if previous.is_a?(Ops::Set) && previous.value.as_s?.nil?
          raise Errors::InvalidOp.new("append after a non-string set at #{JSON.format(op.path)}")
        end
        (@tails[index] ||= Array(String).new) << op.text
      else
        @ops[index] = op
        @tails.delete(index)
      end
    end

    private def materialize : Array(Op)
      return @ops if @tails.empty?
      @tails.each do |index, chunks|
        case previous = @ops[index]
        when Ops::Append
          @ops[index] = Ops::Append.new(previous.path, join(previous.text, chunks))
        when Ops::Set
          @ops[index] = Ops::Set.new(previous.path, ::JSON::Any.new(join(previous.value.as_s, chunks)))
        else
        end
      end
      @ops
    end

    private def join(head : String, chunks : Array(String)) : String
      String.build(head.bytesize + chunks.sum(&.bytesize)) do |io|
        io << head
        chunks.each { |chunk| io << chunk }
      end
    end
  end
end
