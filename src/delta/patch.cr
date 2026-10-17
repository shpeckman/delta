# src/delta/patch.cr
require "./edit"
require "./tokenizer"

module Delta
  module Patch
    extend self

    class Error < Exception
    end

    HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

    struct Line
      getter kind    : Edit::Kind
      getter content : String

      def initialize(@kind : Edit::Kind, @content : String)
      end

      def_equals_and_hash kind, content
    end

    struct ParsedHunk
      getter a_start : Int32
      getter a_count : Int32
      getter b_start : Int32
      getter b_count : Int32
      getter lines   : Array(Line)

      def initialize(@a_start : Int32, @a_count : Int32, @b_start : Int32, @b_count : Int32, @lines : Array(Line))
      end

      def_equals_and_hash a_start, a_count, b_start, b_count, lines
    end

    struct FilePatch
      getter old_path : String?
      getter new_path : String?
      getter hunks    : Array(ParsedHunk)

      def initialize(@old_path : String?, @new_path : String?, @hunks : Array(ParsedHunk))
      end
    end

    def parse(patch : String) : Array(FilePatch)
      files      = [] of FilePatch
      old_path   = nil.as(String?)
      new_path   = nil.as(String?)
      hunks      = [] of ParsedHunk
      hunk_lines = nil.as(Array(Line)?)
      hunk_head  = {0, 0, 0, 0}
      need_a     = 0
      need_b     = 0

      flush_hunk = -> do
        if lines = hunk_lines
          hunks << ParsedHunk.new(hunk_head[0], hunk_head[1], hunk_head[2], hunk_head[3], lines)
          hunk_lines = nil
        end
      end
      flush_file = -> do
        flush_hunk.call
        unless hunks.empty?
          files << FilePatch.new(old_path, new_path, hunks)
          hunks = [] of ParsedHunk
        end
        old_path = nil
        new_path = nil
      end

      patch.each_line(chomp: false) do |raw|
        if raw.starts_with?("--- ")
          flush_file.call
          old_path = raw.byte_slice(4).chomp
        elsif raw.starts_with?("+++ ")
          new_path = raw.byte_slice(4).chomp
        elsif md = HUNK_HEADER.match(raw)
          flush_hunk.call
          a_s        = md[1].to_i
          a_c        = (md[2]? || "1").to_i
          b_s        = md[3].to_i
          b_c        = (md[4]? || "1").to_i
          hunk_head  = {a_c == 0 ? a_s : a_s - 1, a_c, b_c == 0 ? b_s : b_s - 1, b_c}
          hunk_lines = [] of Line
          need_a     = a_c
          need_b     = b_c
        elsif raw.starts_with?('\\') && (lines = hunk_lines) && !lines.empty?
          last    = lines[-1]
          content = last.content
          content = content.byte_slice(0, content.bytesize - 1) if content.ends_with?('\n')
          lines[-1] = Line.new(last.kind, content)
        elsif (lines = hunk_lines) && (need_a > 0 || need_b > 0)
          if raw == "\n" || raw.empty?
            lines << Line.new(Edit::Kind::Equal, "\n")
            need_a -= 1
            need_b -= 1
            next
          end
          kind = case raw[0]
                 when ' ' then Edit::Kind::Equal
                 when '-' then Edit::Kind::Delete
                 when '+' then Edit::Kind::Insert
                 else          next
                 end
          content = raw.byte_slice(1)
          lines << Line.new(kind, content)
          case kind
          when .equal?
            need_a -= 1
            need_b -= 1
          when .delete?
            need_a -= 1
          when .insert?
            need_b -= 1
          end
        end
      end
      flush_file.call
      files
    end

    def render(files : Array(FilePatch)) : String
      String.build do |io|
        files.each do |fp|
          if old = fp.old_path
            io << "--- " << old << '\n'
          end
          if new = fp.new_path
            io << "+++ " << new << '\n'
          end
          fp.hunks.each do |hunk|
            io << "@@ -"
            write_range(io, hunk.a_start, hunk.a_count)
            io << " +"
            write_range(io, hunk.b_start, hunk.b_count)
            io << " @@\n"
            hunk.lines.each do |line|
              prefix = case line.kind
                       when .equal?  then ' '
                       when .delete? then '-'
                       when .insert? then '+'
                       end
              io << prefix
              io << line.content
              unless line.content.ends_with?('\n')
                io << '\n'
                io << "\\ No newline at end of file\n"
              end
            end
          end
        end
      end
    end

    def apply(source : String, patch : String) : String
      files = parse(patch)
      fp    = files.first? || raise Error.new("patch contains no hunks")
      apply_file(source, fp)
    end

    def apply(source : String, patch : String, *, reverse : Bool = false, fuzz : Int32 = 0) : String
      patch = Patch.reverse(patch) if reverse
      files = parse(patch)
      fp    = files.first? || raise Error.new("patch contains no hunks")
      apply_file(source, fp, fuzz: fuzz)
    end

    def reverse(patch : String) : String
      files = parse(patch).map do |fp|
        hunks = fp.hunks.map do |hunk|
          lines = hunk.lines.map do |line|
            kind = case line.kind
                   when .delete? then Edit::Kind::Insert
                   when .insert? then Edit::Kind::Delete
                   else               Edit::Kind::Equal
                   end
            Line.new(kind, line.content)
          end
          ParsedHunk.new(hunk.b_start, hunk.b_count, hunk.a_start, hunk.a_count, lines)
        end
        FilePatch.new(fp.new_path, fp.old_path, hunks)
      end
      render(files)
    end

    def apply_file(source : String, fp : FilePatch, *, fuzz : Int32 = 0) : String
      lines     = Tokenizer::Lines.split(source)
      positions = Array(Int32).new(fp.hunks.size, 0)
      min_pos   = 0
      fp.hunks.each_with_index do |hunk, i|
        pos = find_position(lines, hunk, min_pos, fuzz)
        positions[i] = pos
        min_pos = pos + hunk.lines.count { |l| !l.kind.insert? }
      end

      String.build do |io|
        idx = 0
        fp.hunks.each_with_index do |hunk, hi|
          pos = positions[hi]
          while idx < pos
            io.write(lines.line_at(idx))
            idx += 1
          end
          hunk.lines.each do |l|
            case l.kind
            when .equal?
              io.write(lines.line_at(idx))
              idx += 1
            when .delete?
              idx += 1
            when .insert?
              io << l.content
            end
          end
        end
        while idx < lines.size
          io.write(lines.line_at(idx))
          idx += 1
        end
      end
    end

    def apply_to_dir(patch : String, root : String, *, strip : Int32 = 1, fuzz : Int32 = 0) : Array(String)
      actions  = [] of {String, String, Bool}
      affected = [] of String
      parse(patch).each do |fp|
        if fp.old_path == "/dev/null"
          new_path = fp.new_path || raise Error.new("missing new path")
          stripped = stripped_path(new_path, strip)
          result   = apply_file("", fp, fuzz: fuzz)
          actions << {stripped, result, false}
          affected << stripped
        elsif fp.new_path == "/dev/null"
          old_path = fp.old_path || raise Error.new("missing old path")
          stripped = stripped_path(old_path, strip)
          result   = apply_file(read_file(root, stripped), fp, fuzz: fuzz)
          unless result.empty?
            raise Error.new("deletion produced content for #{stripped}")
          end
          actions << {stripped, "", true}
          affected << stripped
        else
          old_path     = fp.old_path || raise Error.new("missing old path")
          new_path     = fp.new_path || raise Error.new("missing new path")
          old_stripped = stripped_path(old_path, strip)
          new_stripped = stripped_path(new_path, strip)
          result       = apply_file(read_file(root, old_stripped), fp, fuzz: fuzz)
          actions << {new_stripped, result, false}
          affected << new_stripped
        end
      end
      actions.each do |action|
        path, content, delete = action
        if delete
          File.delete(File.join(root, path))
        else
          Dir.mkdir_p(File.dirname(File.join(root, path)))
          File.write(File.join(root, path), content)
        end
      end
      affected
    end

    private def read_file(root : String, path : String) : String
      File.read(File.join(root, path))
    rescue ex : File::NotFoundError
      raise Error.new("missing file: #{path}")
    end

    private def stripped_path(path : String, strip : Int32) : String
      return path if path == "/dev/null"
      raise Error.new("absolute path: #{path}") if path.starts_with?('/')
      parts = path.split('/')
      parts = parts.size > strip ? parts[strip..] : [] of String
      raise Error.new("path traversal: #{path}") if parts.any? { |part| part == ".." }
      stripped = parts.join('/')
      raise Error.new("empty path: #{path}") if stripped.empty?
      stripped
    end

    private def write_range(io : IO, start : Int32, count : Int32) : Nil
      io << (count == 0 ? start : start + 1)
      io << ',' << count unless count == 1
    end

    private def find_position(lines : Tokenizer::Lines, hunk : ParsedHunk, min_pos : Int32, fuzz : Int32) : Int32
      base = Math.max(hunk.a_start, min_pos)
      if fuzz == 0
        offset = 0
        loop do
          fwd = base + offset
          return fwd if fwd <= lines.size && match_errors(lines, fwd, hunk) == 0
          bwd = base - offset
          return bwd if offset > 0 && bwd >= min_pos && match_errors(lines, bwd, hunk) == 0
          offset += 1
          if fwd > lines.size && bwd < min_pos
            raise Error.new("hunk @@ -#{hunk.a_start},#{hunk.a_count} +#{hunk.b_start},#{hunk.b_count} @@ does not apply")
          end
        end
      else
        best_pos    = -1
        best_errors = Int32::MAX
        best_dist   = Int32::MAX
        pos         = min_pos
        while pos <= lines.size
          errors = match_errors(lines, pos, hunk)
          if errors && errors <= fuzz
            dist = (pos - base).abs
            if errors < best_errors || (errors == best_errors && dist < best_dist)
              best_errors = errors
              best_dist   = dist
              best_pos    = pos
            end
          end
          pos += 1
        end
        if best_pos < 0
          raise Error.new("hunk @@ -#{hunk.a_start},#{hunk.a_count} +#{hunk.b_start},#{hunk.b_count} @@ does not apply")
        end
        best_pos
      end
    end

    private def match_errors(lines : Tokenizer::Lines, pos : Int32, hunk : ParsedHunk) : Int32?
      idx    = pos
      errors = 0
      hunk.lines.each do |l|
        next if l.kind.insert?
        return nil if idx >= lines.size
        if lines.line_at(idx) == l.content.to_slice
          idx += 1
        elsif l.kind.equal?
          errors += 1
          idx += 1
        else
          return nil
        end
      end
      errors
    end
  end
end
