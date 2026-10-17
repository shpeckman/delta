# src/delta/patience.cr
module Delta
  class Patience < Algorithm
    def diff(a : Slice(Int32), b : Slice(Int32)) : Array(Edit)
      diff(a, b, nil)
    end

    def diff(a : Slice(Int32), b : Slice(Int32), ws : Workspace?) : Array(Edit)
      max   = a.size + b.size
      edits = ws ? ws.edits : [] of Edit
      edits.clear
      return edits if max == 0
      if ws
        vf, vb = ws.v_arrays(max)
        counts_a, counts_b = ws.counts
        bpos_map = ws.bpos_map
        dest     = ws.normalized
      else
        bound    = max + (max + 1) // 2
        vf       = Slice(Int32).new(2 * bound + 3, 0)
        vb       = Slice(Int32).new(2 * bound + 3, 0)
        counts_a = Hash(Int32, Int32).new(0)
        counts_b = Hash(Int32, Int32).new(0)
        bpos_map = Hash(Int32, Int32).new
        dest     = [] of Edit
      end
      rec(a, 0, a.size, b, 0, b.size, Myers.new, vf, vb, counts_a, counts_b, bpos_map, edits)
      normalize(edits, dest)
    end

    private def rec(a : Slice(Int32), a_lo : Int32, a_hi : Int32,
                    b : Slice(Int32), b_lo : Int32, b_hi : Int32,
                    myers : Myers, vf : Slice(Int32), vb : Slice(Int32),
                    counts_a : Hash(Int32, Int32), counts_b : Hash(Int32, Int32),
                    bpos_map : Hash(Int32, Int32), edits : Array(Edit)) : Nil
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

      n  = n0 - p - s
      m  = m0 - p - s
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
        counts_a.clear
        counts_b.clear
        bpos_map.clear
        i = am
        while i < ae
          counts_a[a[i]] += 1
          i += 1
        end
        j = bm
        while j < be
          tok = b[j]
          counts_b[tok] += 1
          bpos_map[tok] = j unless bpos_map.has_key?(tok)
          j += 1
        end

        uniques = [] of {Int32, Int32}
        i       = am
        while i < ae
          tok = a[i]
          if counts_a[tok] == 1 && counts_b[tok]? == 1
            uniques << {i, bpos_map[tok]}
          end
          i += 1
        end

        anchors = lis(uniques)
        if anchors.empty?
          myers.diff_region(a, am, ae, b, bm, be, vf, vb, edits)
        else
          pa = am
          pb = bm
          anchors.each do |ai, bi|
            rec(a, pa, ai, b, pb, bi, myers, vf, vb, counts_a, counts_b, bpos_map, edits)
            emit(edits, Kind::Equal, ai, 1, bi, 1)
            pa = ai + 1
            pb = bi + 1
          end
          rec(a, pa, ae, b, pb, be, myers, vf, vb, counts_a, counts_b, bpos_map, edits)
        end
      end

      emit(edits, Kind::Equal, ae, s, be, s) if s > 0
    end

    private def lis(pairs : Array({Int32, Int32})) : Array({Int32, Int32})
      tails = [] of Int32
      prev  = Array(Int32).new(pairs.size, -1)
      pairs.each_with_index do |pair, idx|
        y  = pair[1]
        lo = 0
        hi = tails.size
        while lo < hi
          mid = (lo + hi) // 2
          if pairs[tails[mid]][1] < y
            lo = mid + 1
          else
            hi = mid
          end
        end
        prev[idx] = lo > 0 ? tails[lo - 1] : -1
        if lo == tails.size
          tails << idx
        else
          tails[lo] = idx
        end
      end
      result = [] of {Int32, Int32}
      unless tails.empty?
        i = tails[-1]
        while i >= 0
          result << pairs[i]
          i = prev[i]
        end
        result.reverse!
      end
      result
    end
  end
end
