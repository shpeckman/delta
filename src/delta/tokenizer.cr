# src/delta/tokenizer.cr
require "./whitespace"

module Delta::Tokenizer
  extend self

  class Interner(T)
    @map : Hash(T, Int32)
    @next = 0

    def initialize(initial_capacity : Int32 = 0)
      @map = initial_capacity > 0 ? Hash(T, Int32).new(initial_capacity: initial_capacity) : Hash(T, Int32).new
    end

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

  struct Lines
    getter source : String
    getter offsets : Array(Int32)
    getter tokens : Slice(Int32)
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
      stop = index + 1 < offsets.size ? offsets[index + 1] : source.bytesize
      source.to_slice[start, stop - start]
    end

    def each_line(& : Bytes ->) : Nil
      size.times { |i| yield line_at(i) }
    end
  end

  WHITESPACE_RUN = /\s+/

  def tokenize(a : Indexable(T), b : Indexable(T)) : {Slice(Int32), Slice(Int32)} forall T
    interner = Interner(T).new(Math.min(a.size + b.size, 8192))
    tokens_a = Slice(Int32).new(a.size) { |i| interner.token(a[i]) }
    tokens_b = Slice(Int32).new(b.size) { |i| interner.token(b[i]) }
    {tokens_a, tokens_b}
  end

  def lines(old_source : String, new_source : String, *,
            whitespace : Whitespace = Whitespace::None, ignore_case : Bool = false) : {Lines, Lines}
    offs_a = offsets(old_source)
    offs_b = offsets(new_source)
    capacity = Math.min(Math.max(offs_a.size, offs_b.size), 8192)
    if whitespace.none? && !ignore_case
      interner = Interner(Bytes).new(capacity)
      {tokenize_lines(old_source, offs_a, interner), tokenize_lines(new_source, offs_b, interner)}
    else
      interner = Interner(String).new(capacity)
      {tokenize_lines_normalized(old_source, offs_a, interner, whitespace, ignore_case),
       tokenize_lines_normalized(new_source, offs_b, interner, whitespace, ignore_case)}
    end
  end

  def normalize(line : Bytes, whitespace : Whitespace, ignore_case : Bool) : String
    size = line.size
    has_0x0Au8 = size > 0 && line[size - 1] == 0x0Au8
    len = has_0x0Au8 ? size - 1 : size
    content = String.new(line[0, len])
    content = content.downcase if ignore_case
    case whitespace
    when .all?    then content = content.gsub(WHITESPACE_RUN, "")
    when .amount? then content = content.gsub(WHITESPACE_RUN, " ")
    end
    has_0x0Au8 ? content + "\n" : content
  end

  def offsets(source : String) : Array(Int32)
    bytes = source.to_slice
    return [] of Int32 if bytes.empty?
    count = 1
    i = 0
    while i < bytes.size
      count += 1 if bytes[i] == 0x0Au8 && i + 1 < bytes.size
      i += 1
    end
    result = Array(Int32).new(count)
    result << 0
    i = 0
    while i < bytes.size
      result << i + 1 if bytes[i] == 0x0Au8 && i + 1 < bytes.size
      i += 1
    end
    result
  end

  private def tokenize_lines(source : String, offs : Array(Int32), interner : Interner(Bytes)) : Lines
    bytes = source.to_slice
    blank = nil.as(Int32?)
    tokens = Slice(Int32).new(offs.size) do |i|
      start = offs[i]
      stop = i + 1 < offs.size ? offs[i + 1] : bytes.size
      line = bytes[start, stop - start]
      tok = interner.token(line)
      blank = tok if blank.nil? && line.size == 1 && line[0] == 0x0Au8
      tok
    end
    Lines.new(source, offs, tokens, blank)
  end

  private def tokenize_lines_normalized(source : String, offs : Array(Int32), interner : Interner(String),
                                        whitespace : Whitespace, ignore_case : Bool) : Lines
    bytes = source.to_slice
    blank = nil.as(Int32?)
    tokens = Slice(Int32).new(offs.size) do |i|
      start = offs[i]
      stop = i + 1 < offs.size ? offs[i + 1] : bytes.size
      line = bytes[start, stop - start]
      tok = interner.token(normalize(line, whitespace, ignore_case))
      blank = tok if blank.nil? && line.size == 1 && line[0] == 0x0Au8
      tok
    end
    Lines.new(source, offs, tokens, blank)
  end
end
