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

    protected def finalize(edits : Array(Edit)) : Array(Edit)
      swapped = [] of Edit
      i = 0
      while i < edits.size
        e = edits[i]
        if e.kind.insert? && i + 1 < edits.size &&
           (nxt = edits[i + 1]).kind.delete? &&
           nxt.a_pos == e.a_pos && nxt.b_pos == e.b_pos + e.b_len
          swapped << nxt
          swapped << e
          i += 2
        else
          swapped << e
          i += 1
        end
      end
      merged = [] of Edit
      swapped.each do |e|
        if (last = merged.last?) && last.kind == e.kind &&
           last.a_pos + last.a_len == e.a_pos && last.b_pos + last.b_len == e.b_pos
          merged[-1] = Edit.new(e.kind, last.a_pos, last.a_len + e.a_len, last.b_pos, last.b_len + e.b_len)
        else
          merged << e
        end
      end
      merged
    end
  end
end
