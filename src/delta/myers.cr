# src/delta/myers.cr
module Delta
  class Myers < Algorithm
    def diff(a : Slice(Int32), b : Slice(Int32)) : Array(Edit)
      edits = [] of Edit
      max = a.size + b.size
      return edits if max == 0
      bound = max + (max + 1) // 2
      vf = Slice(Int32).new(2 * bound + 3, 0)
      vb = Slice(Int32).new(2 * bound + 3, 0)
      diff_region(a, 0, a.size, b, 0, b.size, vf, vb, edits)
      edits
    end

    def diff_region(a : Slice(Int32), a_lo : Int32, a_hi : Int32,
                    b : Slice(Int32), b_lo : Int32, b_hi : Int32,
                    vf : Slice(Int32), vb : Slice(Int32), edits : Array(Edit)) : Nil
      n0 = a_hi - a_lo
      m0 = b_hi - b_lo
      return if n0 == 0 && m0 == 0

      p = 0
      while p < n0 && p < m0 && a[a_lo + p] == b[b_lo + p]
        p += 1
      end
      s = 0
      while s < n0 - p && s < m0 - p && a[a_hi - 1 - s] == b[b_hi - 1 - s]
        s += 1
      end

      n = n0 - p - s
      m = m0 - p - s
      am = a_lo + p
      bm = b_lo + p

      emit(edits, Kind::Equal, a_lo, p, b_lo, p) if p > 0

      if n == 0 && m > 0
        emit(edits, Kind::Insert, am, 0, bm, m)
      elsif m == 0 && n > 0
        emit(edits, Kind::Delete, am, n, bm, 0)
      elsif n > 0 && m > 0
        x, y = middle_snake(a, am, b, bm, n, m, vf, vb)
        diff_region(a, am, am + x, b, bm, bm + y, vf, vb, edits)
        diff_region(a, am + x, a_hi - s, b, bm + y, b_hi - s, vf, vb, edits)
      end

      emit(edits, Kind::Equal, a_hi - s, s, b_hi - s, s) if s > 0
    end

    private def middle_snake(a : Slice(Int32), a_lo : Int32, b : Slice(Int32), b_lo : Int32,
                             n : Int32, m : Int32, vf : Slice(Int32), vb : Slice(Int32)) : {Int32, Int32}
      max = n + m
      delta = n - m
      off = max + 1
      half = (max + 1) // 2

      d = 0
      while d <= half
        k = -d
        while k <= d
          if d == 0
            x = 0
          elsif k == -d
            x = vf[off + k + 1]
          elsif k == d
            x = vf[off + k - 1] + 1
          else
            x = Math.max(vf[off + k + 1], vf[off + k - 1] + 1)
          end
          y = x - k
          while x < n && y < m && a[a_lo + x] == b[b_lo + y]
            x += 1
            y += 1
          end
          vf[off + k] = x
          if delta.odd? && d >= 1 && (delta - (d - 1)) <= k <= (delta + (d - 1)) && vf[off + k] >= vb[off + k]
            return {x, y}
          end
          k += 2
        end

        k = delta - d
        while k <= delta + d
          if d == 0
            x = n
          elsif k == delta - d
            x = vb[off + k + 1] - 1
          elsif k == delta + d
            x = vb[off + k - 1]
          else
            x = Math.min(vb[off + k + 1] - 1, vb[off + k - 1])
          end
          y = x - k
          while x > 0 && y > 0 && a[a_lo + x - 1] == b[b_lo + y - 1]
            x -= 1
            y -= 1
          end
          vb[off + k] = x
          if delta.even? && -d <= k <= d && vf[off + k] >= vb[off + k]
            return {x, y}
          end
          k += 2
        end

        d += 1
      end
      raise "delta: myers middle snake not found"
    end
  end
end
