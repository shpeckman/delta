# src/delta/merge.cr
require "./tokenizer"
require "./edit"

module Delta
  struct MergeResult
    getter text : String
    getter conflicts : Int32

    def initialize(@text : String, @conflicts : Int32)
    end

    def clean? : Bool
      conflicts == 0
    end
  end

  module Merge
    extend self

    struct Change
      getter a_start : Int32
      getter a_len : Int32
      getter b_pos : Int32
      getter b_len : Int32

      def initialize(@a_start : Int32, @a_len : Int32, @b_pos : Int32, @b_len : Int32)
      end
    end

    def changes(edits : Array(Edit)) : Array(Change)
      result = [] of Change
      i = 0
      while i < edits.size
        if edits[i].kind.equal?
          i += 1
          next
        end
        a_s = edits[i].a_pos
        a_e = edits[i].a_pos + edits[i].a_len
        b_s = edits[i].b_pos
        b_e = edits[i].b_pos + edits[i].b_len
        while i < edits.size && !edits[i].kind.equal?
          e = edits[i]
          a_s = Math.min(a_s, e.a_pos)
          a_e = Math.max(a_e, e.a_pos + e.a_len)
          b_s = Math.min(b_s, e.b_pos)
          b_e = Math.max(b_e, e.b_pos + e.b_len)
          i += 1
        end
        result << Change.new(a_s, a_e - a_s, b_s, b_e - b_s)
      end
      result
    end

    def merge(base : String, ours : String, theirs : String,
              ours_label : String = "ours", theirs_label : String = "theirs",
              algorithm : Algorithm = Myers.new) : MergeResult
      lb = Lines.split(base)
      lo = Lines.split(ours)
      lt = Lines.split(theirs)
      co = changes(Delta.diff_lines(base, ours, algorithm: algorithm))
      ct = changes(Delta.diff_lines(base, theirs, algorithm: algorithm))

      conflicts = 0
      text = String.build do |io|
        pos = 0
        i = 0
        j = 0
        while i < co.size || j < ct.size
          gstart = if j >= ct.size
                     co[i].a_start
                   elsif i >= co.size
                     ct[j].a_start
                   else
                     Math.min(co[i].a_start, ct[j].a_start)
                   end
          gend = gstart
          gi = i
          gj = j
          loop do
            extended = false
            while gi < co.size && co[gi].a_start <= gend
              gend = Math.max(gend, co[gi].a_start + co[gi].a_len)
              gi += 1
              extended = true
            end
            while gj < ct.size && ct[gj].a_start <= gend
              gend = Math.max(gend, ct[gj].a_start + ct[gj].a_len)
              gj += 1
              extended = true
            end
            break unless extended
          end

          while pos < gstart
            io.write(lb.line_at(pos))
            pos += 1
          end

          ours_rep = replay(lb, lo, gstart, gend, co[i...gi])
          theirs_rep = replay(lb, lt, gstart, gend, ct[gj...gj])
          if i == gi
            io << theirs_rep
          elsif j == gj
            io << ours_rep
          elsif ours_rep == theirs_rep
            io << ours_rep
          else
            conflicts += 1
            io << "<<<<<<< " << ours_label << '\n'
            write_block(io, ours_rep)
            io << "=======\n"
            write_block(io, theirs_rep)
            io << ">>>>>>> " << theirs_label << '\n'
          end

          i = gi
          j = gj
          pos = gend
        end
        while pos < lb.size
          io.write(lb.line_at(pos))
          pos += 1
        end
      end
      MergeResult.new(text, conflicts)
    end

    private def replay(base : Lines, side : Lines, gstart : Int32, gend : Int32, changes : Array(Change)) : String
      String.build do |io|
        pos = gstart
        changes.each do |ch|
          while pos < ch.a_start
            io.write(base.line_at(pos))
            pos += 1
          end
          ch.b_len.times { |k| io.write(side.line_at(ch.b_pos + k)) }
          pos = ch.a_start + ch.a_len
        end
        while pos < gend
          io.write(base.line_at(pos))
          pos += 1
        end
      end
    end

    private def write_block(io : IO, content : String) : Nil
      return if content.empty?
      io << content
      io << '\n' unless content.ends_with?('\n')
    end
  end
end
