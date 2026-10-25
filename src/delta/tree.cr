# src/delta/tree.cr
module Delta::Tree
  macro define(node_type, key_type)
    alias Container = Hash({{key_type}}, {{node_type}}) | Array({{node_type}})

    module Ops
      record Replace, value : {{node_type}}
      record Set, path : Path, value : {{node_type}}
      record Delete, path : Path
      record Append, path : Path, text : String
      record Trim, path : Path, count : Int32
      record Splice, path : Path, index : Int32, remove : Int32, items : Array({{node_type}})
      record Move, path : Path, permutation : Array(Int32)
    end

    alias Op = Ops::Replace | Ops::Set | Ops::Delete | Ops::Append | Ops::Trim | Ops::Splice | Ops::Move

    def self.leaf?(op : Op) : Bool
      case op
      when Ops::Append
        true
      when Ops::Set
        !container?(op.value)
      else
        false
      end
    end

    def self.diff(base : {{node_type}}, value : {{node_type}}) : Array(Op)
      ops = Array(Op).new
      diff_into(base, value, Path.new, ops)
      ops
    end

    protected def self.diff_into(base : {{node_type}}, value : {{node_type}}, path : Path, ops : Array(Op)) : Nil
      return if identical?(base, value)
      if (ah = hash?(base)) && (bh = hash?(value))
        diff_hash(ah, bh, path, ops)
      elsif (aa = array?(base)) && (ba = array?(value))
        diff_array(aa, ba, path, ops)
      elsif (as = string?(base)) && (bs = string?(value))
        diff_string(as, bs, path, ops)
      elsif base != value
        ops << (path.empty? ? Ops::Replace.new(value) : Ops::Set.new(path.dup, value))
      end
    end

    protected def self.diff_hash(a : Hash({{key_type}}, {{node_type}}), b : Hash({{key_type}}, {{node_type}}), path : Path, ops : Array(Op)) : Nil
      a.each_key do |key|
        unless b.has_key?(key)
          path << key
          ops << Ops::Delete.new(path.dup)
          path.pop
        end
      end
      b.each do |key, child|
        if previous = a[key]?
          path << key
          diff_into(previous, child, path, ops)
          path.pop
        else
          path << key
          ops << Ops::Set.new(path.dup, child)
          path.pop
        end
      end
    end

    protected def self.diff_array(a : Array({{node_type}}), b : Array({{node_type}}), path : Path, ops : Array(Op)) : Nil
      if a.size == b.size
        a.each_with_index do |child, index|
          path << index
          diff_into(child, b[index], path, ops)
          path.pop
        end
        return
      end
      limit = Math.min(a.size, b.size)
      prefix = 0
      while prefix < limit && same_value?(a[prefix], b[prefix])
        prefix += 1
      end
      suffix = 0
      while suffix < limit - prefix && same_value?(a[a.size - 1 - suffix], b[b.size - 1 - suffix])
        suffix += 1
      end
      ops << Ops::Splice.new(path.dup, prefix, a.size - prefix - suffix, b[prefix...(b.size - suffix)])
    end

    protected def self.diff_string(a : String, b : String, path : Path, ops : Array(Op)) : Nil
      return if a == b
      if b.bytesize > a.bytesize && b.starts_with?(a)
        ops << Ops::Append.new(path.dup, b.byte_slice(a.bytesize))
      elsif a.bytesize > b.bytesize && a.ends_with?(b)
        ops << Ops::Trim.new(path.dup, a.size - b.size)
      else
        ops << (path.empty? ? Ops::Replace.new(wrap_string(b)) : Ops::Set.new(path.dup, wrap_string(b)))
      end
    end

    protected def self.same_value?(a : {{node_type}}, b : {{node_type}}) : Bool
      identical?(a, b) || a == b
    end

    class Writer
      getter root : {{node_type}}

      def initialize(@root : {{node_type}}, @shared : Bool = true)
        @owned = ::Set(UInt64).new
        @keep = Array(Container).new
      end

      def read(path : Path) : {{node_type}}?
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
        if (h = hash?(parent))
          h[key(op.path)] = op.value
        elsif (a = array?(parent))
          index = index(op.path)
          if index < a.size
            a[index] = op.value
          elsif index == a.size
            a << op.value
          else
            raise Errors::InvalidPath.new("index #{index} past the end of #{format(op.path[0...-1])}")
          end
        end
      end

      private def apply_delete(op : Ops::Delete) : Nil
        raise Errors::InvalidPath.new("cannot delete the root") if op.path.empty?
        parent = container(op.path, op.path.size - 1)
        if (h = hash?(parent))
          name = key(op.path)
          raise Errors::InvalidPath.new("no key at #{format(op.path)}") unless h.has_key?(name)
          h.delete(name)
        elsif (a = array?(parent))
          index = index(op.path)
          raise Errors::InvalidPath.new("no element at #{format(op.path)}") unless index < a.size
          a.delete_at(index)
        end
      end

      private def apply_append(op : Ops::Append) : Nil
        update_string(op.path) { |text| text + op.text }
      end

      private def apply_trim(op : Ops::Trim) : Nil
        update_string(op.path) do |text|
          raise Errors::InvalidOp.new("cannot trim #{op.count} characters from #{text.size} at #{format(op.path)}") if op.count > text.size
          text[op.count..]
        end
      end

      private def apply_splice(op : Ops::Splice) : Nil
        list = array(op.path)
        if op.index > list.size || op.index + op.remove > list.size
          raise Errors::InvalidPath.new("splice #{op.index}+#{op.remove} outside #{list.size} elements at #{format(op.path)}")
        end
        list[op.index, op.remove] = op.items
      end

      private def apply_move(op : Ops::Move) : Nil
        list = array(op.path)
        unless op.permutation.size == list.size && op.permutation.sort == (0...list.size).to_a
          raise Errors::InvalidOp.new("permutation does not match #{list.size} elements at #{format(op.path)}")
        end
        source = list.dup
        op.permutation.each_with_index { |from, to| list[to] = source[from] }
      end

      private def update_string(path : Path, & : String -> String) : Nil
        if path.empty?
          text = string?(@root) || raise Errors::InvalidPath.new("root is not a string")
          @root = wrap_string(yield text)
          return
        end
        parent = container(path, path.size - 1)
        if (h = hash?(parent))
          name = key(path)
          text = h[name]?.try { |child| string?(child) } || raise Errors::InvalidPath.new("no string at #{format(path)}")
          h[name] = wrap_string(yield text)
        elsif (a = array?(parent))
          index = index(path)
          text = a[index]?.try { |child| string?(child) } || raise Errors::InvalidPath.new("no string at #{format(path)}")
          a[index] = wrap_string(yield text)
        end
      end

      private def array(path : Path) : Array({{node_type}})
        node = container(path, path.size)
        array?(node) || raise Errors::InvalidPath.new("no array at #{format(path)}")
      end

      private def container(path : Path, depth : Int32) : {{node_type}}
        @root = own(@root, path, 0)
        node = @root
        depth.times do |level|
          segment = path[level]
          child = lookup(node, segment) || raise Errors::InvalidPath.new("nothing at #{format(path[0..level])}")
          owned = own(child, path, level + 1)
          store(node, segment, owned) unless identical?(child, owned)
          node = owned
        end
        node
      end

      private def own(node : {{node_type}}, path : Path, level : Int32) : {{node_type}}
        if (h = hash?(node))
          return node if !@shared || @owned.includes?(h.object_id)
          claim(h.dup)
        elsif (a = array?(node))
          return node if !@shared || @owned.includes?(a.object_id)
          claim(a.dup)
        else
          raise Errors::InvalidPath.new("no container at #{format(path[0...level])}")
        end
      end

      private def claim(copy : Container) : {{node_type}}
        @owned << copy.object_id
        @keep << copy
        wrap_container(copy)
      end

      private def wrap_container(copy : Container) : {{node_type}}
        case copy
        in Hash({{key_type}}, {{node_type}})
          wrap_hash(copy)
        in Array({{node_type}})
          wrap_array(copy)
        end
      end

      private def lookup(node : {{node_type}}, segment : Segment) : {{node_type}}?
        if (h = hash?(node))
          key = segment.as?({{key_type}})
          key ? h[key]? : nil
        elsif (a = array?(node))
          index = segment.as?(Int32)
          index ? a[index]? : nil
        end
      end

      private def store(node : {{node_type}}, segment : Segment, value : {{node_type}}) : Nil
        if (h = hash?(node))
          h[segment.as({{key_type}})] = value
        elsif (a = array?(node))
          a[segment.as(Int32)] = value
        end
      end

      private def key(path : Path) : {{key_type}}
        path.last.as?({{key_type}}) || raise Errors::InvalidPath.new("expected a key at #{format(path)}")
      end

      private def index(path : Path) : Int32
        path.last.as?(Int32) || raise Errors::InvalidPath.new("expected an index at #{format(path)}")
      end
    end

    def self.apply_immutable(base : {{node_type}}, ops : Array(Op)) : {{node_type}}
      writer = Writer.new(base)
      ops.each { |op| writer.apply(op) }
      writer.root
    end

    def self.apply_immutable_batches(base : {{node_type}}, batches : Enumerable(Array(Op))) : {{node_type}}
      writer = Writer.new(base)
      batches.each { |ops| ops.each { |op| writer.apply(op) } }
      writer.root
    end

    def self.apply(replica : {{node_type}}, ops : Array(Op)) : {{node_type}}
      writer = Writer.new(replica, shared: false)
      ops.each { |op| writer.apply(op) }
      writer.root
    end
  end
end
