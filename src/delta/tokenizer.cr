# src/delta/tokenizer.cr
module Delta
  NL = 0x0Au8

  struct Lines
    getter source : String
    getter offsets : Array(Int32)
    getter tokens : Slice(Int32)

    def initialize(@source : String, @offsets : Array(Int32), @tokens : Slice(Int32))
    end

    def self.split(source : String) : Lines
      new(source, Tokenizer.offsets(source), Slice(Int32).new(0))
    end

    def size : Int32
      offsets.size
    end

    def line_at(index : Int32) : Bytes
      start = offsets[index]
      stop = index + 1 < offsets.size ? offsets[index + 1] : source.bytesize
      source.to_slice[start, stop - start]
    end

    def each_line(& : Bytes ->) : Nil
      size.times { |i| yield line_at(i) }
    end
  end

  class Interner(T)
    @map = Hash(T, Int32).new
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

  module Tokenizer
    extend self

    def tokenize(a : Indexable(T), b : Indexable(T)) : {Slice(Int32), Slice(Int32)} forall T
      interner = Interner(T).new
      tokens_a = Slice(Int32).new(a.size) { |i| interner.token(a[i]) }
      tokens_b = Slice(Int32).new(b.size) { |i| interner.token(b[i]) }
      {tokens_a, tokens_b}
    end

    def lines(old_source : String, new_source : String) : {Lines, Lines}
      interner = Interner(Bytes).new
      {tokenize_lines(old_source, interner), tokenize_lines(new_source, interner)}
    end

    def offsets(source : String) : Array(Int32)
      bytes = source.to_slice
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
      offs = offsets(source)
      bytes = source.to_slice
      tokens = Slice(Int32).new(offs.size) do |i|
        start = offs[i]
        stop = i + 1 < offs.size ? offs[i + 1] : bytes.size
        interner.token(bytes[start, stop - start])
      end
      Lines.new(source, offs, tokens)
    end
  end
end
