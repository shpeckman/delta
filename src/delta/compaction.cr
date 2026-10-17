# src/delta/compaction.cr
require "./edit"

module Delta
  module Compaction
    extend self

    def compact(edits : Array(Edit), a : Slice(Int32), b : Slice(Int32), blank : Int32?) : Array(Edit)
      result = [] of Edit
      anchor_a = 0
      anchor_b = 0
      i = 0
      while i < edits.size
        if edits[i].kind.equal?
          i += 1
          next
        end

        as = edits[i].a_pos
        bs = edits[i].b_pos
        alen = 0
        blen = 0
        while i < edits.size && !edits[i].kind.equal?
          alen += edits[i].a_len
          blen += edits[i].b_len
          i += 1
        end
        ae = as + alen
        be = bs + blen

        up = 0
        while can_slide_up(a, b, as - up, ae - up, bs - up, be - up, alen, blen, anchor_a, anchor_b)
          up += 1
        end
        top_as = as - up
        top_bs = bs - up
        down = 0
        while can_slide_down(a, b, top_as + down, top_bs + down, alen, blen)
          down += 1
        end

        best_d = 0
        best_score = score(a, top_as, top_as + alen, blank)
        d = 1
        while d <= down
          s = score(a, top_as + d, top_as + d + alen, blank)
          if s > best_score
            best_score = s
            best_d = d
          end
          d += 1
        end

        nas = top_as + best_d
        nbs = top_bs + best_d
        gap = nas - anchor_a
        emit_equal(result, anchor_a, gap, anchor_b) if gap > 0
        result << Edit.new(Kind::Delete, nas, alen, nbs, 0) if alen > 0
        result << Edit.new(Kind::Insert, nas, 0, nbs, blen) if blen > 0
        anchor_a = nas + alen
        anchor_b = nbs + blen
      end

      tail = a.size - anchor_a
      emit_equal(result, anchor_a, tail, anchor_b) if tail > 0
      result
    end

    private def can_slide_up(a : Slice(Int32), b : Slice(Int32), as : Int32, ae : Int32,
                             bs : Int32, be : Int32, alen : Int32, blen : Int32,
                             anchor_a : Int32, anchor_b : Int32) : Bool
      return false if as <= anchor_a || bs <= anchor_b
      return false if alen > 0 && a[as - 1] != a[ae - 1]
      return false if blen > 0 && b[bs - 1] != b[be - 1]
      true
    end

    private def can_slide_down(a : Slice(Int32), b : Slice(Int32), as : Int32,
                               bs : Int32, alen : Int32, blen : Int32) : Bool
      return false if as + alen >= a.size || bs + blen >= b.size
      return false if alen > 0 && a[as] != a[as + alen]
      return false if blen > 0 && b[bs] != b[bs + blen]
      true
    end

    private def score(a : Slice(Int32), as : Int32, ae : Int32, blank : Int32?) : Int32
      s = 0
      if as == 0 || (blank && a[as - 1] == blank)
        s += 2
      end
      if ae == a.size || (blank && ae < a.size && a[ae] == blank)
        s += 1
      end
      s
    end

    private def emit_equal(result : Array(Edit), a_pos : Int32, len : Int32, b_pos : Int32) : Nil
      if (last = result.last?) && last.kind.equal? && last.a_pos + last.a_len == a_pos
        result[-1] = Edit.new(Kind::Equal, last.a_pos, last.a_len + len, last.b_pos, last.b_len + len)
      else
        result << Edit.new(Kind::Equal, a_pos, len, b_pos, len)
      end
    end
  end
end
