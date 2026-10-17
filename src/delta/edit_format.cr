# src/delta/edit_format.cr
require "./edit"
require "./tokenizer"
require "./patch"

module Delta
  class EditFormatError < Exception
  end

  module EditFormat
    extend self

    enum Kind
      Whole
      Replace
      Unified
    end

    struct Block
      getter search  : String
      getter replace : String

      def initialize(@search : String, @replace : String)
      end

      def_equals_and_hash search, replace
    end

    struct FileEdit
      getter kind    : Kind
      getter path    : String
      getter content : String?
      getter blocks  : Array(Block)

      def initialize(@kind : Kind, @path : String, @content : String? = nil, @blocks : Array(Block) = [] of Block)
      end

      def_equals_and_hash kind, path, content, blocks
    end

    FENCE    = "```"
    HEAD     = /^<{5,9} SEARCH>?\s*$/
    DIVIDER  = /^={5,9}\s*$/
    UPDATED  = /^>{5,9} REPLACE\s*$/
    DOT_LINE = /^\s*\.\.\.\n$/

    def parse(text : String, valid_files : Array(String)? = nil) : Array(FileEdit)
      return parse_udiff(text) if looks_like_udiff?(text)
      return parse_replace(text, valid_files) if looks_like_replace?(text)
      parse_whole(text, valid_files)
    end

    def parse_whole(text : String, valid_files : Array(String)? = nil) : Array(FileEdit)
      lines   = text.lines(chomp: false)
      edits   = [] of FileEdit
      fname   = nil.as(String?)
      content = nil.as(Array(String)?)
      i       = 0
      while i < lines.size
        line = lines[i]
        if line.starts_with?(FENCE)
          if fname
            edits << FileEdit.new(Kind::Whole, fname, content.not_nil!.join)
            fname   = nil
            content = nil
          else
            filename = i > 0 ? strip_filename(lines[i - 1]) : nil
            filename = strip_filename(line) if filename.nil?
            if filename.nil?
              if valid_files && valid_files.size == 1
                filename = valid_files[0]
              else
                raise EditFormatError.new("no filename before fence")
              end
            end
            fname   = filename
            content = [] of String
          end
        elsif fname
          content.not_nil! << line
        end
        i += 1
      end
      edits << FileEdit.new(Kind::Whole, fname, content.not_nil!.join) if fname
      dedupe_whole(edits)
    end

    def parse_replace(text : String, valid_files : Array(String)? = nil) : Array(FileEdit)
      lines   = text.lines(chomp: false)
      flat    = [] of {String, Block}
      current = nil.as(String?)
      i       = 0
      while i < lines.size
        if HEAD.matches?(lines[i].strip)
          filename = find_filename(lines, i, valid_files) || current
          if filename.nil?
            raise EditFormatError.new("missing filename before SEARCH/REPLACE block")
          end
          current  = filename
          i += 1
          original = [] of String
          while i < lines.size && !DIVIDER.matches?(lines[i].strip)
            original << lines[i]
            i += 1
          end
          raise EditFormatError.new("expected `=======` in SEARCH/REPLACE block") if i >= lines.size
          i += 1
          updated = [] of String
          while i < lines.size && !UPDATED.matches?(lines[i].strip) && !DIVIDER.matches?(lines[i].strip)
            updated << lines[i]
            i += 1
          end
          raise EditFormatError.new("expected `>>>>>>> REPLACE` in SEARCH/REPLACE block") if i >= lines.size
          flat << {filename, Block.new(original.join, updated.join)}
        end
        i += 1
      end
      coalesce(flat)
    end

    def parse_udiff(text : String) : Array(FileEdit)
      lines = text.lines(chomp: false)
      edits = [] of FileEdit
      i     = 0
      while i < lines.size
        if lines[i].starts_with?(FENCE)
          j = i + 1
          while j < lines.size && !lines[j].starts_with?(FENCE)
            j += 1
          end
          edits.concat(parse_udiff_block(lines[i + 1, j - i - 1]))
          i = j + 1
        else
          i += 1
        end
      end
      edits
    end

    def apply_file(source : String, edit : FileEdit) : String
      return edit.content || "" if edit.kind.whole?
      result = source
      edit.blocks.each do |block|
        result = search_replace(result, block.search, block.replace) ||
          raise EditFormatError.new(block_error(edit.path, block))
      end
      result
    end

    def apply(text : String, root : String) : Array(String)
      edits = parse(text)
      state = {} of String => String
      order = [] of String
      edits.each do |edit|
        path = safe_path(edit.path)
        unless state.has_key?(path)
          full = File.join(root, path)
          state[path] = File.exists?(full) ? File.read(full) : ""
          order << path
        end
        state[path] = apply_file(state[path], edit)
      end
      order.each do |path|
        full = File.join(root, path)
        Dir.mkdir_p(File.dirname(full))
        File.write(full, state[path])
      end
      order
    end

    def search_replace(source : String, before : String, after : String) : String?
      return source + after if before.strip.empty?
      whole, whole_lines = prep(source)
      part, part_lines   = prep(before)
      replace, replace_lines = prep(after)

      if res = perfect_replace(whole_lines, part_lines, replace_lines)
        return res
      end
      if res = whitespace_replace(whole_lines, part_lines, replace_lines)
        return res
      end
      if part_lines.size > 2 && part_lines[0].strip.empty?
        skip = part_lines[1..]
        if res = perfect_replace(whole_lines, skip, replace_lines)
          return res
        end
        if res = whitespace_replace(whole_lines, skip, replace_lines)
          return res
        end
      end
      try_dotdotdots(whole, part, replace)
    end

    private def looks_like_udiff?(text : String) : Bool
      lines = text.lines(chomp: false)
      lines.each_index.any? do |i|
        lines[i].starts_with?(FENCE) && i + 2 < lines.size &&
          lines[i + 1].starts_with?("--- ") && lines[i + 2].starts_with?("+++ ")
      end
    end

    private def looks_like_replace?(text : String) : Bool
      text.each_line.any? { |l| HEAD.matches?(l.strip) }
    end

    private def dedupe_whole(edits : Array(FileEdit)) : Array(FileEdit)
      seen   = Set(String).new
      result = [] of FileEdit
      edits.each { |e| result << e if seen.add?(e.path) }
      result
    end

    private def coalesce(flat : Array({String, Block})) : Array(FileEdit)
      edits = [] of FileEdit
      flat.each do |(path, block)|
        if !edits.empty? && edits.last.path == path
          edits.last.blocks << block
        else
          edits << FileEdit.new(Kind::Replace, path, nil, [block])
        end
      end
      edits
    end

    private def strip_filename(filename : String) : String?
      s = filename.strip
      return nil if s.empty? || s == "..."
      if s.starts_with?(FENCE)
        candidate = s.byte_slice(FENCE.bytesize)
        return candidate if !candidate.empty? && (candidate.includes?('.') || candidate.includes?('/'))
        return nil
      end
      s = s.rstrip(':')
      s = s.lstrip('#')
      s = s.strip
      s = s.strip('`')
      s = s.strip('*')
      s = s.strip
      s.empty? ? nil : s
    end

    private def find_filename(lines : Array(String), before : Int32, valid_files : Array(String)?) : String?
      filenames = [] of String
      i         = before - 1
      stop      = Math.max(0, before - 3)
      while i >= stop
        line = lines[i]
        if fn = strip_filename(line)
          filenames << fn unless fn.starts_with?('<') || fn.starts_with?('=') || fn.starts_with?('>')
        end
        break unless line.starts_with?(FENCE)
        i -= 1
      end
      return nil if filenames.empty?
      if valid_files
        filenames.each { |f| return f if valid_files.includes?(f) }
        filenames.each do |f|
          valid_files.each { |v| return v if f == File.basename(v) }
        end
      end
      filenames.each { |f| return f if f.includes?('.') || f.includes?('/') }
      filenames.first
    end

    private def parse_udiff_block(lines : Array(String)) : Array(FileEdit)
      edits = [] of FileEdit
      i     = 0
      while i < lines.size
        if lines[i].starts_with?("--- ") && i + 1 < lines.size && lines[i + 1].starts_with?("+++ ")
          path   = udiff_path(lines[i + 1], lines[i])
          i += 2
          blocks = [] of Block
          while i < lines.size
            break if lines[i].starts_with?("--- ") && i + 1 < lines.size && lines[i + 1].starts_with?("+++ ")
            if lines[i].starts_with?("@@ ")
              before = [] of String
              after  = [] of String
              i += 1
              while i < lines.size
                l = lines[i]
                break if l.starts_with?("@@ ")
                break if l.starts_with?("--- ") && i + 1 < lines.size && lines[i + 1].starts_with?("+++ ")
                unless l.starts_with?("\\")
                  case l[0]?
                  when ' '
                    before << l.byte_slice(1)
                    after << l.byte_slice(1)
                  when '-'
                    before << l.byte_slice(1)
                  when '+'
                    after << l.byte_slice(1)
                  end
                end
                i += 1
              end
              blocks << Block.new(before.join, after.join)
            else
              i += 1
            end
          end
          edits << FileEdit.new(Kind::Unified, path, nil, blocks)
        else
          i += 1
        end
      end
      edits
    end

    private def udiff_path(plus : String, minus : String) : String
      a = minus.byte_slice(4).strip
      b = plus.byte_slice(4).strip
      return strip_ab(a) if b == "/dev/null"
      strip_ab(b)
    end

    private def strip_ab(path : String) : String
      return path if path == "/dev/null"
      return path.byte_slice(2) if path.starts_with?("a/") || path.starts_with?("b/")
      path
    end

    private def prep(content : String) : {String, Array(String)}
      s = if content.empty? || content.ends_with?('\n')
            content
          else
            content + "\n"
          end
      {s, s.empty? ? [] of String : s.lines(chomp: false)}
    end

    private def perfect_replace(whole_lines : Array(String), part_lines : Array(String), replace_lines : Array(String)) : String?
      part_len = part_lines.size
      return nil if part_len == 0 || part_len > whole_lines.size
      i = 0
      while i <= whole_lines.size - part_len
        j = 0
        while j < part_len && whole_lines[i + j] == part_lines[j]
          j += 1
        end
        if j == part_len
          return whole_lines[0, i].join + replace_lines.join + whole_lines[i + part_len, whole_lines.size - i - part_len].join
        end
        i += 1
      end
      nil
    end

    private def whitespace_replace(whole_lines : Array(String), part_lines : Array(String), replace_lines : Array(String)) : String?
      leading = [] of Int32
      part_lines.each { |p| leading << (p.size - p.lstrip.size) if p.strip != "" }
      replace_lines.each { |p| leading << (p.size - p.lstrip.size) if p.strip != "" }
      if !leading.empty? && leading.min != 0
        num = leading.min
        part_lines = part_lines.map { |p| p.strip != "" ? p[num..] : p }
        replace_lines = replace_lines.map { |p| p.strip != "" ? p[num..] : p }
      end
      part_len = part_lines.size
      return nil if part_len == 0 || part_len > whole_lines.size
      i = 0
      while i <= whole_lines.size - part_len
        add_leading = match_but_for_leading_whitespace(whole_lines[i, part_len], part_lines)
        if add_leading
          new_replace = replace_lines.map { |r| r.strip != "" ? add_leading + r : r }
          return whole_lines[0, i].join + new_replace.join + whole_lines[i + part_len, whole_lines.size - i - part_len].join
        end
        i += 1
      end
      nil
    end

    private def match_but_for_leading_whitespace(whole_lines : Array(String), part_lines : Array(String)) : String?
      num = whole_lines.size
      num.times do |i|
        return nil unless whole_lines[i].lstrip == part_lines[i].lstrip
      end
      add = nil.as(String?)
      num.times do |i|
        if whole_lines[i].strip != ""
          candidate = whole_lines[i][0, whole_lines[i].size - part_lines[i].size]
          if add.nil?
            add = candidate
          elsif add != candidate
            return nil
          end
        end
      end
      add
    end

    private def try_dotdotdots(whole : String, part : String, replace : String) : String?
      part_pieces    = dot_split(part)
      replace_pieces = dot_split(replace)
      return nil if part_pieces.size != replace_pieces.size
      return nil if part_pieces.size == 1
      idx = 1
      while idx < part_pieces.size
        return nil unless part_pieces[idx] == replace_pieces[idx]
        idx += 2
      end
      result = whole
      idx    = 0
      while idx < part_pieces.size
        p = part_pieces[idx]
        r = replace_pieces[idx]
        idx += 2
        next if p.empty? && r.empty?
        if p.empty?
          result += "\n" unless result.ends_with?('\n')
          result += r
          next
        end
        count = count_substring(result, p)
        return nil if count == 0 || count > 1
        result = replace_first(result, p, r)
      end
      result
    end

    private def dot_split(s : String) : Array(String)
      pieces  = [] of String
      current = ""
      s.lines(chomp: false).each do |line|
        if DOT_LINE.matches?(line)
          pieces << current
          pieces << line
          current = ""
        else
          current += line
        end
      end
      pieces << current
      pieces
    end

    private def count_substring(s : String, sub : String) : Int32
      return 0 if sub.empty?
      count = 0
      idx   = 0
      while idx <= s.bytesize
        found = s.byte_index(sub, idx)
        break unless found
        count += 1
        idx = found + sub.bytesize
      end
      count
    end

    private def replace_first(s : String, sub : String, replacement : String) : String
      idx = s.byte_index(sub)
      return s unless idx
      s.byte_slice(0, idx) + replacement + s.byte_slice(idx + sub.bytesize)
    end

    private def block_error(path : String, block : Block) : String
      String.build do |io|
        io << "SEARCH/REPLACE block failed to match in " << path << '\n'
        io << "<<<<<<< SEARCH\n"
        io << block.search
        io << "=======\n"
        io << block.replace
        io << ">>>>>>> REPLACE\n"
      end
    end

    private def safe_path(path : String) : String
      raise EditFormatError.new("absolute path: #{path}") if path.starts_with?('/')
      parts = path.split('/')
      raise EditFormatError.new("path traversal: #{path}") if parts.any? { |p| p == ".." }
      raise EditFormatError.new("empty path: #{path}") if parts.empty? || parts.all?(&.empty?)
      path
    end
  end
end
