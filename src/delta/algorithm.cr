# src/delta/algorithm.cr
module Delta
  abstract class Algorithm
    abstract def diff(a : Slice(Int32), b : Slice(Int32)) : Array(Edit)

    protected def emit(edits : Array(Edit), kind : Kind, a_pos : Int32, a_len : Int32, b_pos : Int32, b_len : Int32) : Nil
      return if a_len == 0 && b_len == 0
      if (last = edits.last?) && last.kind == kind &&
         last.a_pos + last.a_len == a_pos && last.b_pos + last.b_len == b_pos
        edits[-1] = Edit.new(kind, last.a_pos, last.a_len + a_len, last.b_pos, last.b_len + b_len)
      else
        edits << Edit.new(kind, a_pos, a_len, b_pos, b_len)
      end
    end
  end
end
