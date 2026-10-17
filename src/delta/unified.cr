# src/delta/unified.cr
module Delta
  module Unified
    extend self

    def render(old_lines : Tokenizer::Lines, new_lines : Tokenizer::Lines, hunks : Array(Hunk),
               old_path : String?, new_path : String?) : String
      String.build do |io|
        render(io, old_lines, new_lines, hunks, old_path, new_path)
      end
    end

    def render(io : IO, old_lines : Tokenizer::Lines, new_lines : Tokenizer::Lines, hunks : Array(Hunk),
               old_path : String?, new_path : String?) : Nil
      return if hunks.empty?
      if old_path && new_path
        io << "--- " << old_path << '\n'
        io << "+++ " << new_path << '\n'
      end
      hunks.each do |hunk|
        io << "@@ -"
        write_range(io, hunk.a_start, hunk.a_count)
        io << " +"
        write_range(io, hunk.b_start, hunk.b_count)
        io << " @@\n"
        hunk.ops.each do |e|
          case e.kind
          when .equal?  then write_lines(io, old_lines, e.a_pos, e.a_len, ' ')
          when .delete? then write_lines(io, old_lines, e.a_pos, e.a_len, '-')
          when .insert? then write_lines(io, new_lines, e.b_pos, e.b_len, '+')
          end
        end
      end
    end

    private def write_range(io : IO, start : Int32, count : Int32) : Nil
      io << (count == 0 ? start : start + 1)
      io << ',' << count unless count == 1
    end

    private def write_lines(io : IO, lines : Tokenizer::Lines, start : Int32, count : Int32, prefix : Char) : Nil
      count.times do |i|
        io << prefix
        content = lines.line_at(start + i)
        io.write(content)
        unless content[-1] == '\n'.ord.to_u8
          io << '\n'
          io << "\\ No newline at end of file" << '\n'
        end
      end
    end
  end
end
