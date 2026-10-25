# src/delta/tree.cr
module Delta::Tree
  macro define(node_type, key_type, adapter)
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
      elsif (sa = string?(base)) && (sb = string?(value))
        diff_string(sa, sb, path, ops)
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
        if (h = {{adapter}}.hash?(parent))
          h[key(op.path)] = op.value
        elsif (a = {{adapter}}.array?(parent))
          index = index(op.path)
          if index < a.size
            a[index] = op.value
          elsif index == a.size
            a << op.value
          else
            raise Errors::InvalidPath.new("index #{index} past the end of {{adapter}}.format(op.path[0...-1])")
          end
        end
      end

      private def apply_delete(op : Ops::Delete) : Nil
        raise Errors::InvalidPath.new("cannot delete the root") if op.path.empty?
        parent = container(op.path, op.path.size - 1)
        if (h = {{adapter}}.hash?(parent))
          name = key(op.path)
          raise Errors::InvalidPath.new("no key at {{adapter}}.format(op.path)") unless h.has_key?(name)
          h.delete(name)
        elsif (a = {{adapter}}.array?(parent))
          index = index(op.path)
          raise Errors::InvalidPath.new("no element at {{adapter}}.format(op.path)") unless index < a.size
          a.delete_at(index)
        end
      end

      private def apply_append(op : Ops::Append) : Nil
        update_string(op.path) { |text| text + op.text }
      end

      private def apply_trim(op : Ops::Trim) : Nil
        update_string(op.path) do |text|
          raise Errors::InvalidOp.new("cannot trim #{op.count} characters from #{text.size} at {{adapter}}.format(op.path)") if op.count > text.size
          text[op.count..]
        end
      end

      private def apply_splice(op : Ops::Splice) : Nil
        list = array(op.path)
        if op.index > list.size || op.index + op.remove > list.size
          raise Errors::InvalidPath.new("splice #{op.index}+#{op.remove} outside #{list.size} elements at {{adapter}}.format(op.path)")
        end
        list[op.index, op.remove] = op.items
      end

      private def apply_move(op : Ops::Move) : Nil
        list = array(op.path)
        unless op.permutation.size == list.size && op.permutation.sort == (0...list.size).to_a
          raise Errors::InvalidOp.new("permutation does not match #{list.size} elements at {{adapter}}.format(op.path)")
        end
        source = list.dup
        op.permutation.each_with_index { |from, to| list[to] = source[from] }
      end

      private def update_string(path : Path, & : String -> String) : Nil
        if path.empty?
          text = {{adapter}}.string?(@root) || raise Errors::InvalidPath.new("root is not a string")
          @root = {{adapter}}.wrap_string(yield text)
          return
        end
        parent = container(path, path.size - 1)
        if (h = {{adapter}}.hash?(parent))
          name = key(path)
          text = h[name]?.try { |child| {{adapter}}.string?(child) } || raise Errors::InvalidPath.new("no string at {{adapter}}.format(path)")
          h[name] = {{adapter}}.wrap_string(yield text)
        elsif (a = {{adapter}}.array?(parent))
          index = index(path)
          text = a[index]?.try { |child| {{adapter}}.string?(child) } || raise Errors::InvalidPath.new("no string at {{adapter}}.format(path)")
          a[index] = {{adapter}}.wrap_string(yield text)
        end
      end

      private def array(path : Path) : Array({{node_type}})
        node = container(path, path.size)
        {{adapter}}.array?(node) || raise Errors::InvalidPath.new("no array at {{adapter}}.format(path)")
      end

      private def container(path : Path, depth : Int32) : {{node_type}}
        @root = own(@root, path, 0)
        node = @root
        depth.times do |level|
          segment = path[level]
          child = lookup(node, segment) || raise Errors::InvalidPath.new("nothing at {{adapter}}.format(path[0..level])")
          owned = own(child, path, level + 1)
          store(node, segment, owned) unless {{adapter}}.identical?(child, owned)
          node = owned
        end
        node
      end

      private def own(node : {{node_type}}, path : Path, level : Int32) : {{node_type}}
        if (h = {{adapter}}.hash?(node))
          return node if !@shared || @owned.includes?(h.object_id)
          claim(h.dup)
        elsif (a = {{adapter}}.array?(node))
          return node if !@shared || @owned.includes?(a.object_id)
          claim(a.dup)
        else
          raise Errors::InvalidPath.new("no container at {{adapter}}.format(path[0...level])")
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
          {{adapter}}.wrap_hash(copy)
        in Array({{node_type}})
          {{adapter}}.wrap_array(copy)
        end
      end

      private def lookup(node : {{node_type}}, segment : Segment) : {{node_type}}?
        if (h = {{adapter}}.hash?(node))
          key = segment.as?({{key_type}})
          key ? h[key]? : nil
        elsif (a = {{adapter}}.array?(node))
          index = segment.as?(Int32)
          index ? a[index]? : nil
        end
      end

      private def store(node : {{node_type}}, segment : Segment, value : {{node_type}}) : Nil
        if (h = {{adapter}}.hash?(node))
          h[segment.as({{key_type}})] = value
        elsif (a = {{adapter}}.array?(node))
          a[segment.as(Int32)] = value
        end
      end

      private def key(path : Path) : {{key_type}}
        path.last.as?({{key_type}}) || raise Errors::InvalidPath.new("expected a key at {{adapter}}.format(path)")
      end

      private def index(path : Path) : Int32
        path.last.as?(Int32) || raise Errors::InvalidPath.new("expected an index at {{adapter}}.format(path)")
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

    class PendingOps
      LIMIT = 10_000

      getter limit : Int32

      def initialize(@limit : Int32 = LIMIT)
        @ops = Array(Op).new
        @tails = Hash(Int32, Array(String)).new
        @leaves = Hash(Path, Int32).new
        @overflow = false
      end

      def push(ops : Array(Op)) : Nil
        ops.each { |op| fold(op) }
      end

      def push(op : Op) : Nil
        fold(op)
      end

      def overflow? : Bool
        @overflow
      end

      def empty? : Bool
        !@overflow && @ops.empty?
      end

      def size : Int32
        @ops.size
      end

      def take(current : {{node_type}}) : Array(Op)
        ops = @overflow ? [Ops::Replace.new(current)] of Op : materialize
        clear
        ops
      end

      def clear : Nil
        @ops = Array(Op).new
        @tails = Hash(Int32, Array(String)).new
        @leaves = Hash(Path, Int32).new
        @overflow = false
      end

      private def fold(op : Op) : Nil
        if op.is_a?(Ops::Replace)
          clear
          @ops << op
          return
        end
        return if @overflow

        leaf = {{adapter}}.leaf?(op)
        if leaf && (index = @leaves[op.path]?)
          merge(index, op)
        else
          @leaves.clear unless leaf
          @ops << op
          @leaves[op.path] = @ops.size - 1 if leaf
        end

        if @ops.size > @limit
          @ops = Array(Op).new
          @tails = Hash(Int32, Array(String)).new
          @leaves = Hash(Path, Int32).new
          @overflow = true
        end
      end

      private def merge(index : Int32, op : Op) : Nil
        case op
        when Ops::Append
          previous = @ops[index]
          if previous.is_a?(Ops::Set) && {{adapter}}.string?(previous.value).nil?
            raise Errors::InvalidOp.new("append after a non-string set at {{adapter}}.format(op.path)")
          end
          (@tails[index] ||= Array(String).new) << op.text
        else
          @ops[index] = op
          @tails.delete(index)
        end
      end

      private def materialize : Array(Op)
        return @ops if @tails.empty?
        @tails.each do |index, chunks|
          case previous = @ops[index]
          when Ops::Append
            @ops[index] = Ops::Append.new(previous.path, join(previous.text, chunks))
          when Ops::Set
            text = {{adapter}}.string?(previous.value) || raise Errors::InvalidOp.new("append after a non-string set")
            @ops[index] = Ops::Set.new(previous.path, {{adapter}}.wrap_string(join(text, chunks)))
          else
          end
        end
        @ops
      end

      private def join(head : String, chunks : Array(String)) : String
        String.build(head.bytesize + chunks.sum(&.bytesize)) do |io|
          io << head
          chunks.each { |chunk| io << chunk }
        end
      end
    end

    class Prepared
      enum Status
        Pending
        Aborted
        Adopted
      end

      getter tracker : Tracker
      getter base : {{node_type}}
      getter value : {{node_type}}
      getter ops : Array(Op)
      getter revision : Int64
      getter status : Status

      def initialize(@tracker : Tracker, @base : {{node_type}}, @value : {{node_type}}, @ops : Array(Op), @revision : Int64)
        @status = Status::Pending
      end

      def empty? : Bool
        @ops.empty?
      end

      def abort : Nil
        raise Errors::Settled.new("preparation was already adopted") if @status.adopted?
        @status = Status::Aborted
      end

      protected def adopted! : Nil
        @status = Status::Adopted
      end
    end

    class Tracker
      def initialize(value : {{node_type}})
        @value = value
        @revision = 0_i64
        @mutex = Sync::Mutex.new
      end

      def value : {{node_type}}
        @mutex.synchronize { @value }
      end

      def revision : Int64
        @mutex.synchronize { @revision }
      end

      def begin_change : Change
        @mutex.synchronize { Change.new(self, @value, @revision) }
      end

      def prepare_replace(value : {{node_type}}) : Prepared
        base, revision = @mutex.synchronize { {@value, @revision} }
        if base == value
          Prepared.new(self, base, base, Array(Op).new, revision)
        else
          Prepared.new(self, base, value, [Ops::Replace.new(value)] of Op, revision)
        end
      end

      def adopt(prepared : Prepared) : Nil
        @mutex.synchronize do
          raise Errors::Rejected.new("preparation belongs to another tracker") unless prepared.tracker.same?(self)
          raise Errors::Rejected.new("preparation was aborted") if prepared.status.aborted?
          raise Errors::Rejected.new("preparation was already adopted") if prepared.status.adopted?
          raise Errors::Stale.new("preparation of revision #{prepared.revision} is stale at revision #{@revision}") unless prepared.revision == @revision
          @value = prepared.value
          @revision += 1
          prepared.adopted!
        end
      end

      def change(& : Draft ->) : Prepared
        change = begin_change
        begin
          yield change.root
        rescue ex
          change.abort
          raise ex
        end
        prepared = change.prepare
        adopt(prepared)
        prepared
      end

      def replace(value : {{node_type}}) : Prepared
        prepared = prepare_replace(value)
        adopt(prepared)
        prepared
      end
    end

    class Change
      enum Status
        Open
        Prepared
        Aborted
      end

      getter revision : Int64

      def initialize(@tracker : Tracker, @base : {{node_type}}, @revision : Int64)
        @writer = Writer.new(@base)
        @ops = Array(Op).new
        @status = Status::Open
      end

      def root : Draft
        Draft.new(self, Path.new)
      end

      def value : {{node_type}}
        ensure_open
        @writer.root
      end

      def open? : Bool
        @status.open? && @tracker.revision == @revision
      end

      def prepare : Prepared
        ensure_open
        @status = Status::Prepared
        value = @ops.empty? ? @base : @writer.root
        Prepared.new(@tracker, @base, value, @ops, @revision)
      end

      def abort : Nil
        @status = Status::Aborted if @status.open?
      end

      protected def read(path : Path) : {{node_type}}?
        ensure_open
        @writer.read(path)
      end

      protected def record(op : Op) : Nil
        ensure_open
        @writer.apply(op)
        fold(op)
      end

      private def fold(op : Op) : Nil
        last = @ops.last?
        case op
        when Ops::Replace
          @ops.clear
          @ops << op
        when Ops::Append
          if last.is_a?(Ops::Append) && last.path == op.path
            @ops[-1] = Ops::Append.new(op.path, last.text + op.text)
          elsif last.is_a?(Ops::Set) && last.path == op.path && (text = {{adapter}}.string?(last.value))
            @ops[-1] = Ops::Set.new(op.path, {{adapter}}.wrap_string(text + op.text))
          else
            @ops << op
          end
        when Ops::Set
          if (last.is_a?(Ops::Set) || last.is_a?(Ops::Append)) && last.path == op.path
            @ops[-1] = op
          else
            @ops << op
          end
        else
          @ops << op
        end
      end

      private def ensure_open : Nil
        raise Errors::Settled.new("change is #{@status.to_s.downcase}") unless @status.open?
        raise Errors::Stale.new("change of revision #{@revision} is stale") unless @tracker.revision == @revision
      end
    end

    struct Draft
      getter path : Path

      def initialize(@change : Change, @path : Path)
      end

      def [](key : {{key_type}}) : Draft
        Draft.new(@change, child(key))
      end

      def [](index : Int32) : Draft
        Draft.new(@change, child(index))
      end

      def value : {{node_type}}
        @change.read(@path) || raise Errors::InvalidPath.new("nothing at {{adapter}}.format(@path)")
      end

      def value? : {{node_type}}?
        @change.read(@path)
      end

      def has_key?(key : {{key_type}}) : Bool
        !!{{adapter}}.hash?(value).try(&.has_key?(key))
      end

      def size : Int32
        node = value
        if (h = {{adapter}}.hash?(node))
          h.size
        elsif (a = {{adapter}}.array?(node))
          a.size
        elsif (s = {{adapter}}.string?(node))
          s.size
        else
          raise Errors::InvalidPath.new("no container or string at {{adapter}}.format(@path)")
        end
      end

      def replace(value) : Nil
        placed = {{adapter}}.any(value)
        if @path.empty?
          @change.record(Ops::Replace.new(placed))
        else
          put(@path, placed)
        end
      end

      def []=(key : {{key_type}}, value) : Nil
        put(child(key), {{adapter}}.any(value))
      end

      def []=(index : Int32, value) : Nil
        put(child(index), {{adapter}}.any(value))
      end

      def set(key : {{key_type}} | Int32, value) : Nil
        put(child(key), {{adapter}}.any(value))
      end

      def delete(key : {{key_type}}) : Nil
        @change.record(Ops::Delete.new(child(key)))
      end

      def delete_at(index : Int32) : {{node_type}}
        removed = list[index]? || raise Errors::InvalidPath.new("no element at {{adapter}}.format(child(index))")
        @change.record(Ops::Delete.new(child(index)))
        removed
      end

      def append(key : {{key_type}} | Int32, text : String) : Nil
        return if text.empty?
        @change.record(Ops::Append.new(child(key), text))
      end

      def append(text : String) : Nil
        return if text.empty?
        @change.record(Ops::Append.new(@path.dup, text))
      end

      def trim(key : {{key_type}} | Int32, count : Int32) : Nil
        return if count == 0
        @change.record(Ops::Trim.new(child(key), count))
      end

      def trim(count : Int32) : Nil
        return if count == 0
        @change.record(Ops::Trim.new(@path.dup, count))
      end

      def push(*values) : Nil
        splice(list.size, 0, values.map { |entry| {{adapter}}.any(entry) }.to_a)
      end

      def unshift(*values) : Nil
        splice(0, 0, values.map { |entry| {{adapter}}.any(entry) }.to_a)
      end

      def insert(index : Int32, *values) : Nil
        splice(index, 0, values.map { |entry| {{adapter}}.any(entry) }.to_a)
      end

      def concat(values : Enumerable) : Nil
        splice(list.size, 0, values.map { |entry| {{adapter}}.any(entry) }.to_a)
      end

      def pop : {{node_type}}?
        items = list
        return nil if items.empty?
        removed = items.last
        splice(items.size - 1, 1)
        removed
      end

      def shift : {{node_type}}?
        items = list
        return nil if items.empty?
        removed = items.first
        splice(0, 1)
        removed
      end

      def splice(index : Int32, remove : Int32, items : Array({{node_type}}) = Array({{node_type}}).new) : Nil
        return if remove == 0 && items.empty?
        @change.record(Ops::Splice.new(@path.dup, index, remove, items.map { |entry| {{adapter}}.copy(entry) }))
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

      def sort_by(& : {{node_type}} -> _) : Nil
        items = list
        move((0...items.size).to_a.sort_by! { |index| yield items[index] })
      end

      private def list : Array({{node_type}})
        {{adapter}}.array?(value) || raise Errors::InvalidPath.new("no array at {{adapter}}.format(@path)")
      end

      private def put(path : Path, placed : {{node_type}}) : Nil
        unless {{adapter}}.container?(placed)
          current = @change.read(path)
          return if current && !{{adapter}}.container?(current) && current == placed
        end
        @change.record(Ops::Set.new(path, placed))
      end

      private def rebase(op : Op) : Op
        case op
        in Ops::Replace
          @path.empty? ? Ops::Replace.new({{adapter}}.copy(op.value)) : Ops::Set.new(@path.dup, {{adapter}}.copy(op.value))
        in Ops::Set
          Ops::Set.new(prefixed(op.path), {{adapter}}.copy(op.value))
        in Ops::Delete
          Ops::Delete.new(prefixed(op.path))
        in Ops::Append
          Ops::Append.new(prefixed(op.path), op.text)
        in Ops::Trim
          Ops::Trim.new(prefixed(op.path), op.count)
        in Ops::Splice
          Ops::Splice.new(prefixed(op.path), op.index, op.remove, op.items.map { |entry| {{adapter}}.copy(entry) })
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

    record Frame, value : {{node_type}}, ops : Array(Op), seq : Int64

    class Watch
      enum End
        Stopped
        Retired
        Ended
        Failed
      end

      getter value : {{node_type}}
      getter seq : Int64

      def initialize(@state : State, @value : {{node_type}}, @seq : Int64, limit : Int32 = PendingOps::LIMIT)
        @pending = PendingOps.new(limit)
        @latest = @value
        @latest_seq = @seq
        @lock = Sync::Mutex.new
        @cond = Sync::ConditionVariable.new(@lock)
        @end = nil.as(End?)
        @error = nil.as(Exception?)
      end

      def receive? : Frame?
        @lock.synchronize do
          loop do
            unless @pending.empty?
              ops = @pending.take(@latest)
              @value = @latest
              @seq = @latest_seq
              return Frame.new(@latest, ops, @latest_seq)
            end
            return nil if @end
            @cond.wait
          end
        end
      end

      def each(& : Frame ->) : Nil
        while frame = receive?
          yield frame
        end
      end

      def stop : Nil
        @state.release(self)
        @lock.synchronize do
          @pending.clear
          @end ||= End::Stopped
          @cond.broadcast
        end
      end

      def ended : End?
        @lock.synchronize { @end }
      end

      def error : Exception?
        @lock.synchronize { @error }
      end

      def closed? : Bool
        !ended.nil?
      end

      protected def deliver(value : {{node_type}}, ops : Array(Op), seq : Int64) : Nil
        @lock.synchronize do
          return if @end
          @pending.push(ops)
          @latest = value
          @latest_seq = seq
          @cond.signal
        end
      end

      protected def finish(reason : End, error : Exception? = nil) : Nil
        @lock.synchronize do
          return if @end
          @end = reason
          @error = error
          @cond.broadcast
        end
      end
    end

    class State
      def initialize(value : {{node_type}}, @limit : Int32 = PendingOps::LIMIT)
        @tracker = Tracker.new(value)
        @mutex = Sync::Mutex.new
        @watches = Array(Watch).new
        @seq = 0_i64
        @end = nil.as(Watch::End?)
        @error = nil.as(Exception?)
      end

      def value : {{node_type}}
        @tracker.value
      end

      def seq : Int64
        @mutex.synchronize { @seq }
      end

      def closed? : Bool
        @mutex.synchronize { !@end.nil? }
      end

      def change(& : Draft ->) : Array(Op)
        @mutex.synchronize do
          ensure_open
          prepared = @tracker.change { |draft| yield draft }
          publish(prepared)
          prepared.ops
        end
      end

      def replace(value : {{node_type}}) : Array(Op)
        @mutex.synchronize do
          ensure_open
          prepared = @tracker.replace(value)
          publish(prepared)
          prepared.ops
        end
      end

      def watch : Watch
        @mutex.synchronize do
          watch = Watch.new(self, @tracker.value, @seq, @limit)
          if reason = @end
            watch.finish(reason, @error)
          else
            @watches << watch
          end
          watch
        end
      end

      def watch_count : Int32
        @mutex.synchronize { @watches.size }
      end

      def retire : Nil
        close_with(Watch::End::Retired) do
          @seq += 1
          retired = [Ops::Replace.new({{adapter}}.nil_value)] of Op
          @watches.each &.deliver({{adapter}}.nil_value, retired, @seq)
        end
      end

      def close(error : Exception? = nil) : Nil
        close_with(error ? Watch::End::Failed : Watch::End::Ended, error) { }
      end

      protected def release(watch : Watch) : Nil
        @mutex.synchronize { @watches.delete(watch) }
      end

      private def close_with(reason : Watch::End, error : Exception? = nil, &) : Nil
        @mutex.synchronize do
          return if @end
          yield
          @end = reason
          @error = error
          @watches.each &.finish(reason, error)
          @watches.clear
        end
      end

      private def publish(prepared : Prepared) : Nil
        return if prepared.ops.empty?
        @seq += 1
        @watches.each &.deliver(prepared.value, prepared.ops, @seq)
      end

      private def ensure_open : Nil
        raise Errors::Closed.new("state is #{@end.to_s.downcase}") if @end
      end
    end
  end
end
