# src/delta/words.cr
require "./edit"

module Delta
  module Words
    extend self

    def tokens(source : String) : Array(String)
      result = [] of String
      return result if source.empty?
      reader      = Char::Reader.new(source)
      token_start = 0
      previous_whitespace : Bool? = nil
      while reader.has_next?
        pos        = reader.pos
        whitespace = reader.current_char.whitespace?
        reader.next_char
        if !previous_whitespace.nil? && previous_whitespace != whitespace
          result << source.byte_slice(token_start, pos - token_start)
          token_start = pos
        end
        previous_whitespace = whitespace
      end
      result << source.byte_slice(token_start, source.bytesize - token_start)
      result
    end

    def markup(old_tokens : Array(String), new_tokens : Array(String), edits : Array(Edit)) : String
      String.build do |io|
        edits.each do |edit|
          case edit.kind
          when .equal?
            edit.a_len.times do |i|
              io << old_tokens[edit.a_pos + i]
            end
          when .delete?
            next if edit.a_len == 0
            io << "[-"
            edit.a_len.times do |i|
              io << old_tokens[edit.a_pos + i]
            end
            io << "-]"
          when .insert?
            next if edit.b_len == 0
            io << "{+"
            edit.b_len.times do |i|
              io << new_tokens[edit.b_pos + i]
            end
            io << "+}"
          end
        end
      end
    end
  end
end
