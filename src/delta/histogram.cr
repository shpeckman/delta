# src/delta/histogram.cr
module Delta
  class Histogram < Algorithm
    MAX_CHAIN = 64

    def diff(a : Slice(Int32), b : Slice(Int32)) : Array(Edit)
      edits = [] of Edit
      max = a.size + b.size
      return edits if max == 0
      bound = max + (max + 1) // 2
      vf = Slice(Int32).new(2 * bound + 3, 0)
      vb = Slice(Int32).new(2 * bound + 3, 0)
      rec(a, 0, a.size, b, 0, b.size, Myers.new, vf, vb,
        Hash(Int32, Int32).new(0), Hash(Int32, Int32).new(0), edits)
      normalize(edits)
    end

    private def rec(a : Slice(Int32), a_lo : Int32, a_hi : Int32,
                    b : Slice(Int32), b_lo : Int32, b_hi : Int32,
                    myers : Myers, vf : Slice(Int32), vb : Slice(Int32),
                    counts_a : Hash(Int32, Int32), counts_b : Hash(Int32, Int32),
                    edits : Array(Edit)) : Nil
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
      ae = a_hi - s
      be = b_hi - s

      emit(edits, Kind::Equal, a_lo, p, b_lo, p) if p > 0

      if n == 0 && m > 0
        emit(edits, Kind::Insert, am, 0, bm, m)
      elsif m == 0 && n > 0
        emit(edits, Kind::Delete, am, n, bm, 0)
      elsif n > 0 && m > 0
        if n + m <= MIN_HISTOGRAM
          myers.diff_region(a, am, ae, b, bm, be, vf, vb, edits)
        else
          counts_a.clear
          counts_b.clear
          i = am
          while i < ae
            counts_a[a[i]] += 1
            i += 1
          end
          j = bm
          while j < be
            counts_b[b[j]] += 1
            j += 1
          end

          best_tok = -1
          best_cnt = Int32::MAX
          counts_b.each do |tok, cb|
            if ca = counts_a[tok]?
              total = ca + cb
              if total < best_cnt
                best_tok = tok
                best_cnt = total
              end
            end
          end

          if best_tok == -1 || best_cnt > MAX_CHAIN
            myers.diff_region(a, am, ae, b, bm, be, vf, vb, edits)
          else
            apos = [] of Int32
            bpos = [] of Int32
            i = am
            while i < ae
              apos << i if a[i] == best_tok
              i += 1
            end
            j = bm
            while j < be
              bpos << j if b[j] == best_tok
              j += 1
            end

            ai = apos[0]
            bi = bpos[0]
            best_shift = ((apos[0] - am) - (bpos[0] - bm)).abs
            bidx = 0
            apos.each do |x|
              while bidx + 1 < bpos.size &&
                    ((x - am) - (bpos[bidx + 1] - bm)).abs <= ((x - am) - (bpos[bidx] - bm)).abs
                bidx += 1
              end
              shift = ((x - am) - (bpos[bidx] - bm)).abs
              if shift < best_shift
                best_shift = shift
                ai = x
                bi = bpos[bidx]
              end
            end

            rec(a, am, ai, b, bm, bi, myers, vf, vb, counts_a, counts_b, edits)
            emit(edits, Kind::Equal, ai, 1, bi, 1)
            rec(a, ai + 1, ae, b, bi + 1, be, myers, vf, vb, counts_a, counts_b, edits)
          end
        end
      end

      emit(edits, Kind::Equal, ae, s, be, s) if s > 0
    end
  end
end
