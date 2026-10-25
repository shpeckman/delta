# src/delta/json/writer.cr
module Delta::JSON
  class Writer
    getter root : ::JSON::Any

    def initialize(@root : ::JSON::Any, @shared : Bool = true)
      @owned = ::Set(UInt64).new
      @keep = Array(Container).new
    end

    def read(path : Path) : ::JSON::Any?
      node = @root
      path.each do |segment|
        node = lookup(node, segment) || return nil
      end
      node
    end

    def apply(op : Op) : Nil
      case op
      in Ops::Replace
        @root = op.value
      in Ops::Set
        apply_set(op)
      in Ops::Delete
        apply_delete(op)
      in Ops::Append
        apply_append(op)
      in Ops::Trim
        apply_trim(op)
      in Ops::Splice
        apply_splice(op)
      in Ops::Move
        apply_move(op)
      end
    end

    private def apply_set(op : Ops::Set) : Nil
      if op.path.empty?
        @root = op.value
        return
      end
      parent = container(op.path, op.path.size - 1)
      case raw = parent.raw
      when Hash(String, ::JSON::Any)
        raw[key(op.path)] = op.value
      when Array(::JSON::Any)
        index = index(op.path)
        if index < raw.size
          raw[index] = op.value
        elsif index == raw.size
          raw << op.value
        else
          raise Errors::InvalidPath.new("index #{index} past the end of #{JSON.format(op.path[0...-1])}")
        end
      end
    end

    private def apply_delete(op : Ops::Delete) : Nil
      raise Errors::InvalidPath.new("cannot delete the root") if op.path.empty?
      parent = container(op.path, op.path.size - 1)
      case raw = parent.raw
      when Hash(String, ::JSON::Any)
        name = key(op.path)
        raise Errors::InvalidPath.new("no key at #{JSON.format(op.path)}") unless raw.has_key?(name)
        raw.delete(name)
      when Array(::JSON::Any)
        index = index(op.path)
        raise Errors::InvalidPath.new("no element at #{JSON.format(op.path)}") unless index < raw.size
        raw.delete_at(index)
      end
    end

    private def apply_append(op : Ops::Append) : Nil
      update_string(op.path) { |text| text + op.text }
    end

    private def apply_trim(op : Ops::Trim) : Nil
      update_string(op.path) do |text|
        raise Errors::InvalidOp.new("cannot trim #{op.count} characters from #{text.size} at #{JSON.format(op.path)}") if op.count > text.size
        text[op.count..]
      end
    end

    private def apply_splice(op : Ops::Splice) : Nil
      list = array(op.path)
      if op.index > list.size || op.index + op.remove > list.size
        raise Errors::InvalidPath.new("splice #{op.index}+#{op.remove} outside #{list.size} elements at #{JSON.format(op.path)}")
      end
      list[op.index, op.remove] = op.items
    end

    private def apply_move(op : Ops::Move) : Nil
      list = array(op.path)
      unless op.permutation.size == list.size && op.permutation.sort == (0...list.size).to_a
        raise Errors::InvalidOp.new("permutation does not match #{list.size} elements at #{JSON.format(op.path)}")
      end
      source = list.dup
      op.permutation.each_with_index { |from, to| list[to] = source[from] }
    end

    private def update_string(path : Path, & : String -> String) : Nil
      if path.empty?
        text = @root.as_s? || raise Errors::InvalidPath.new("root is not a string")
        @root = ::JSON::Any.new(yield text)
        return
      end
      parent = container(path, path.size - 1)
      case raw = parent.raw
      when Hash(String, ::JSON::Any)
        name = key(path)
        text = raw[name]?.try(&.as_s?) || raise Errors::InvalidPath.new("no string at #{JSON.format(path)}")
        raw[name] = ::JSON::Any.new(yield text)
      when Array(::JSON::Any)
        index = index(path)
        text = raw[index]?.try(&.as_s?) || raise Errors::InvalidPath.new("no string at #{JSON.format(path)}")
        raw[index] = ::JSON::Any.new(yield text)
      end
    end

    private def array(path : Path) : Array(::JSON::Any)
      container(path, path.size).as_a? || raise Errors::InvalidPath.new("no array at #{JSON.format(path)}")
    end

    private def container(path : Path, depth : Int32) : ::JSON::Any
      @root = own(@root, path, 0)
      node = @root
      depth.times do |level|
        segment = path[level]
        child = lookup(node, segment) || raise Errors::InvalidPath.new("nothing at #{JSON.format(path[0..level])}")
        owned = own(child, path, level + 1)
        store(node, segment, owned) unless JSON.identical?(child, owned)
        node = owned
      end
      node
    end

    private def own(node : ::JSON::Any, path : Path, level : Int32) : ::JSON::Any
      case raw = node.raw
      when Hash(String, ::JSON::Any)
        return node if !@shared || @owned.includes?(raw.object_id)
        claim(raw.dup)
      when Array(::JSON::Any)
        return node if !@shared || @owned.includes?(raw.object_id)
        claim(raw.dup)
      else
        raise Errors::InvalidPath.new("no container at #{JSON.format(path[0...level])}")
      end
    end

    private def claim(copy : Container) : ::JSON::Any
      @owned << copy.object_id
      @keep << copy
      ::JSON::Any.new(copy)
    end

    private def lookup(node : ::JSON::Any, segment : Segment) : ::JSON::Any?
      raw = node.raw
      case segment
      in String
        raw.as?(Hash(String, ::JSON::Any)).try &.[segment]?
      in Int32
        raw.as?(Array(::JSON::Any)).try &.[segment]?
      end
    end

    private def store(node : ::JSON::Any, segment : Segment, value : ::JSON::Any) : Nil
      case raw = node.raw
      when Hash(String, ::JSON::Any)
        raw[segment.as(String)] = value
      when Array(::JSON::Any)
        raw[segment.as(Int32)] = value
      end
    end

    private def key(path : Path) : String
      path.last.as?(String) || raise Errors::InvalidPath.new("expected a key at #{JSON.format(path)}")
    end

    private def index(path : Path) : Int32
      path.last.as?(Int32) || raise Errors::InvalidPath.new("expected an index at #{JSON.format(path)}")
    end
  end

  def self.apply_immutable(base : ::JSON::Any, ops : Array(Op)) : ::JSON::Any
    writer = Writer.new(base)
    ops.each { |op| writer.apply(op) }
    writer.root
  end

  def self.apply_immutable_batches(base : ::JSON::Any, batches : Enumerable(Array(Op))) : ::JSON::Any
    writer = Writer.new(base)
    batches.each { |ops| ops.each { |op| writer.apply(op) } }
    writer.root
  end

  def self.apply(replica : ::JSON::Any, ops : Array(Op)) : ::JSON::Any
    writer = Writer.new(replica, shared: false)
    ops.each { |op| writer.apply(op) }
    writer.root
  end
end
