# src/delta/algorithm.cr
abstract class Delta::Algorithm
  abstract def diff(a : Slice(Int32), b : Slice(Int32)) : Array(Edit)

  def diff(a : Slice(Int32), b : Slice(Int32), ws : Workspace?) : Array(Edit)
    diff(a, b)
  end

  protected def emit(edits : Array(Edit), kind : Edit::Kind, a_pos : Int32, a_len : Int32, b_pos : Int32, b_len : Int32) : Nil
    return if a_len == 0 && b_len == 0
    if (last = edits.last?) && last.kind == kind &&
       last.a_pos + last.a_len == a_pos && last.b_pos + last.b_len == b_pos
      edits[-1] = Edit.new(kind, last.a_pos, last.a_len + a_len, last.b_pos, last.b_len + b_len)
    else
      edits << Edit.new(kind, a_pos, a_len, b_pos, b_len)
    end
  end

  protected def normalize(edits : Array(Edit), dest : Array(Edit)) : Array(Edit)
    dest.clear
    i = 0
    while i < edits.size
      e = edits[i]
      if e.kind.insert? && i + 1 < edits.size &&
         (nxt = edits[i + 1]).kind.delete? &&
         nxt.a_pos == e.a_pos && nxt.b_pos == e.b_pos + e.b_len
        push(dest, nxt)
        push(dest, e)
        i += 2
      else
        push(dest, e)
        i += 1
      end
    end
    dest
  end

  private def push(dest : Array(Edit), e : Edit) : Nil
    if (last = dest.last?) && last.kind == e.kind &&
       last.a_pos + last.a_len == e.a_pos && last.b_pos + last.b_len == e.b_pos
      dest[-1] = Edit.new(e.kind, last.a_pos, last.a_len + e.a_len, last.b_pos, last.b_len + e.b_len)
    else
      dest << e
    end
  end
end

require "./algorithms/myers"
require "./algorithms/histogram"
require "./algorithms/patience"