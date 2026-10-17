# src/delta/hunk.cr
struct Delta::Hunk
  getter a_start : Int32
  getter a_count : Int32
  getter b_start : Int32
  getter b_count : Int32
  getter ops     : Array(Edit)

  def initialize(@ops : Array(Edit))
    @a_start = @ops.first.a_pos
    @b_start = @ops.first.b_pos
    ac       = 0
    bc       = 0
    @ops.each do |e|
      ac += e.a_len
      bc += e.b_len
    end
    @a_count = ac
    @b_count = bc
  end

  def_equals_and_hash a_start, a_count, b_start, b_count, ops

  def self.build(edits : Array(Edit), context : Int32) : Array(Hunk)
    hunks = [] of Hunk
    i     = 0
    n     = edits.size
    while i < n
      if edits[i].kind.equal?
        i += 1
        next
      end

      ops = [] of Edit
      if i > 0
        pe   = edits[i - 1]
        take = Math.min(context, pe.a_len)
        ops << Edit.new(Edit::Kind::Equal, pe.a_pos + pe.a_len - take, take,
          pe.b_pos + pe.b_len - take, take) if take > 0
      end

      while i < n
        e = edits[i]
        if e.kind.equal? && e.a_len > 2 * context
          take = Math.min(context, e.a_len)
          ops << Edit.new(Edit::Kind::Equal, e.a_pos, take, e.b_pos, take) if take > 0
          i += 1
          break
        end
        ops << e
        i += 1
      end

      if ops.last.kind.equal? && ops.last.a_len > context
        last = ops[-1]
        ops[-1] = Edit.new(Edit::Kind::Equal, last.a_pos, context, last.b_pos, context)
      end

      hunks << Hunk.new(ops)
    end
    hunks
  end
end
