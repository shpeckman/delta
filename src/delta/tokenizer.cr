# src/delta/tokenizer.cr
module Delta
  NL = 0x0Au8

  enum Whitespace : UInt8
    None
    Amount
    All
  end

  struct Lines
    getter source      : String
    getter offsets     : Array(Int32)
    getter tokens      : Slice(Int32)
    getter blank_token : Int32?

    def initialize(@source : String, @offsets : Array(Int32), @tokens : Slice(Int32), @blank_token : Int32? = nil)
    end

    def self.split(source : String) : Lines
      new(source, Tokenizer.offsets(source), Slice(Int32).new(0))
    end

    def size : Int32
      offsets.size
    end

    def line_at(index : Int32) : Bytes
      start = offsets[index]
      stop  = index + 1 < offsets.size ? offsets[index + 1] : source.bytesize
      source.to_slice[start, stop - start]
    end

    def each_line(& : Bytes ->) : Nil
      size.times { |i| yield line_at(i) }
    end
  end

  module Tokenizer
    extend self

    class Interner(T)
      @map  = Hash(T, Int32).new
      @next = 0

      def token(value : T) : Int32
        if t = @map[value]?
          t
        else
          t = @next
          @map[value] = t
          @next += 1
          t
        end
      end
    end

    WHITESPACE_RUN = /\s+/

    def tokenize(a : Indexable(T), b : Indexable(T)) : {Slice(Int32), Slice(Int32)} forall T
      interner = Interner(T).new
      tokens_a = Slice(Int32).new(a.size) { |i| interner.token(a[i]) }
      tokens_b = Slice(Int32).new(b.size) { |i| interner.token(b[i]) }
      {tokens_a, tokens_b}
    end

    def lines(old_source : String, new_source : String, *,
              whitespace : Whitespace = Whitespace::None, ignore_case : Bool = false) : {Lines, Lines}
      if whitespace.none? && !ignore_case
        interner = Interner(Bytes).new
        {tokenize_lines(old_source, interner), tokenize_lines(new_source, interner)}
      else
        interner = Interner(String).new
        {tokenize_lines_normalized(old_source, interner, whitespace, ignore_case),
         tokenize_lines_normalized(new_source, interner, whitespace, ignore_case)}
      end
    end

    def normalize(line : Bytes, whitespace : Whitespace, ignore_case : Bool) : String
      size    = line.size
      has_nl  = size > 0 && line[size - 1] == NL
      len     = has_nl ? size - 1 : size
      content = String.new(line[0, len])
      content = content.downcase if ignore_case
      case whitespace
      when .all?    then content = content.gsub(WHITESPACE_RUN, "")
      when .amount? then content = content.gsub(WHITESPACE_RUN, " ")
      end
      has_nl ? content + "\n" : content
    end

    def offsets(source : String) : Array(Int32)
      bytes  = source.to_slice
      result = [] of Int32
      return result if bytes.empty?
      result << 0
      i = 0
      while i < bytes.size
        result << i + 1 if bytes[i] == NL && i + 1 < bytes.size
        i += 1
      end
      result
    end

    private def tokenize_lines(source : String, interner : Interner(Bytes)) : Lines
      offs  = offsets(source)
      bytes = source.to_slice
      blank = nil.as(Int32?)
      tokens = Slice(Int32).new(offs.size) do |i|
        start = offs[i]
        stop  = i + 1 < offs.size ? offs[i + 1] : bytes.size
        line  = bytes[start, stop - start]
        tok   = interner.token(line)
        blank = tok if blank.nil? && line.size == 1 && line[0] == NL
        tok
      end
      Lines.new(source, offs, tokens, blank)
    end

    private def tokenize_lines_normalized(source : String, interner : Interner(String),
                                          whitespace : Whitespace, ignore_case : Bool) : Lines
      offs  = offsets(source)
      bytes = source.to_slice
      blank = nil.as(Int32?)
      tokens = Slice(Int32).new(offs.size) do |i|
        start = offs[i]
        stop  = i + 1 < offs.size ? offs[i + 1] : bytes.size
        line  = bytes[start, stop - start]
        tok   = interner.token(normalize(line, whitespace, ignore_case))
        blank = tok if blank.nil? && line.size == 1 && line[0] == NL
        tok
      end
      Lines.new(source, offs, tokens, blank)
    end
  end
end
