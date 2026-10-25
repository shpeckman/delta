# src/delta/json/draft.cr
module Delta::JSON
  struct Draft
    getter path : Path

    def initialize(@change : Change, @path : Path)
    end

    def [](key : String) : Draft
      Draft.new(@change, child(key))
    end

    def [](index : Int32) : Draft
      Draft.new(@change, child(index))
    end

    def value : ::JSON::Any
      @change.read(@path) || raise Errors::InvalidPath.new("nothing at #{JSON.format(@path)}")
    end

    def value? : ::JSON::Any?
      @change.read(@path)
    end

    def has_key?(key : String) : Bool
      !!value.as_h?.try(&.has_key?(key))
    end

    def size : Int32
      case raw = value.raw
      when Hash(String, ::JSON::Any)
        raw.size
      when Array(::JSON::Any)
        raw.size
      when String
        raw.size
      else
        raise Errors::InvalidPath.new("no container or string at #{JSON.format(@path)}")
      end
    end

    def replace(value) : Nil
      placed = JSON.any(value)
      if @path.empty?
        @change.record(Ops::Replace.new(placed))
      else
        put(@path, placed)
      end
    end

    def []=(key : String, value) : Nil
      put(child(key), JSON.any(value))
    end

    def []=(index : Int32, value) : Nil
      put(child(index), JSON.any(value))
    end

    def set(key : String | Int32, value) : Nil
      put(child(key), JSON.any(value))
    end

    def delete(key : String) : Nil
      @change.record(Ops::Delete.new(child(key)))
    end

    def delete_at(index : Int32) : ::JSON::Any
      removed = list[index]? || raise Errors::InvalidPath.new("no element at #{JSON.format(child(index))}")
      @change.record(Ops::Delete.new(child(index)))
      removed
    end

    def append(key : String | Int32, text : String) : Nil
      return if text.empty?
      @change.record(Ops::Append.new(child(key), text))
    end

    def append(text : String) : Nil
      return if text.empty?
      @change.record(Ops::Append.new(@path.dup, text))
    end

    def trim(key : String | Int32, count : Int32) : Nil
      return if count == 0
      @change.record(Ops::Trim.new(child(key), count))
    end

    def trim(count : Int32) : Nil
      return if count == 0
      @change.record(Ops::Trim.new(@path.dup, count))
    end

    def push(*values) : Nil
      splice(list.size, 0, values.map { |entry| JSON.any(entry) }.to_a)
    end

    def unshift(*values) : Nil
      splice(0, 0, values.map { |entry| JSON.any(entry) }.to_a)
    end

    def insert(index : Int32, *values) : Nil
      splice(index, 0, values.map { |entry| JSON.any(entry) }.to_a)
    end

    def concat(values : Enumerable) : Nil
      splice(list.size, 0, values.map { |entry| JSON.any(entry) }.to_a)
    end

    def pop : ::JSON::Any?
      items = list
      return nil if items.empty?
      removed = items.last
      splice(items.size - 1, 1)
      removed
    end

    def shift : ::JSON::Any?
      items = list
      return nil if items.empty?
      removed = items.first
      splice(0, 1)
      removed
    end

    def splice(index : Int32, remove : Int32, items : Array(::JSON::Any) = Array(::JSON::Any).new) : Nil
      return if remove == 0 && items.empty?
      @change.record(Ops::Splice.new(@path.dup, index, remove, items.map { |entry| JSON.copy(entry) }))
    end

    def move(permutation : Array(Int32)) : Nil
      return if permutation.each_with_index.all? { |from, to| from == to }
      @change.record(Ops::Move.new(@path.dup, permutation.dup))
    end

    def reverse : Nil
      move((0...list.size).to_a.reverse!)
    end

    def apply(ops : Array(Op)) : Nil
      ops.each { |op| @change.record(rebase(op)) }
    end

    def sort_by(& : ::JSON::Any -> _) : Nil
      items = list
      move((0...items.size).to_a.sort_by! { |index| yield items[index] })
    end

    private def list : Array(::JSON::Any)
      value.as_a? || raise Errors::InvalidPath.new("no array at #{JSON.format(@path)}")
    end

    private def put(path : Path, placed : ::JSON::Any) : Nil
      unless JSON.container?(placed)
        current = @change.read(path)
        return if current && !JSON.container?(current) && current == placed
      end
      @change.record(Ops::Set.new(path, placed))
    end

    private def rebase(op : Op) : Op
      case op
      in Ops::Replace
        @path.empty? ? Ops::Replace.new(JSON.copy(op.value)) : Ops::Set.new(@path.dup, JSON.copy(op.value))
      in Ops::Set
        Ops::Set.new(prefixed(op.path), JSON.copy(op.value))
      in Ops::Delete
        Ops::Delete.new(prefixed(op.path))
      in Ops::Append
        Ops::Append.new(prefixed(op.path), op.text)
      in Ops::Trim
        Ops::Trim.new(prefixed(op.path), op.count)
      in Ops::Splice
        Ops::Splice.new(prefixed(op.path), op.index, op.remove, op.items.map { |entry| JSON.copy(entry) })
      in Ops::Move
        Ops::Move.new(prefixed(op.path), op.permutation.dup)
      end
    end

    private def prefixed(path : Path) : Path
      joined = Path.new(@path.size + path.size)
      joined.concat(@path)
      joined.concat(path)
      joined
    end

    private def child(segment : Segment) : Path
      path = Path.new(@path.size + 1)
      path.concat(@path)
      path << segment
      path
    end
  end
end
