# src/delta/json/tracker.cr
module Delta::JSON
  class Prepared
    enum Status
      Pending
      Aborted
      Adopted
    end

    getter tracker  : Tracker
    getter base     : ::JSON::Any
    getter value    : ::JSON::Any
    getter ops      : Array(Op)
    getter revision : Int64
    getter status   : Status

    def initialize(@tracker : Tracker, @base : ::JSON::Any, @value : ::JSON::Any, @ops : Array(Op), @revision : Int64)
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
    def initialize(value : ::JSON::Any)
      @value    = value
      @revision = 0_i64
      @mutex    = Sync::Mutex.new
    end

    def value : ::JSON::Any
      @mutex.synchronize { @value }
    end

    def revision : Int64
      @mutex.synchronize { @revision }
    end

    def begin_change : Change
      @mutex.synchronize { Change.new(self, @value, @revision) }
    end

    def prepare_replace(value : ::JSON::Any) : Prepared
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

    def replace(value : ::JSON::Any) : Prepared
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

    def initialize(@tracker : Tracker, @base : ::JSON::Any, @revision : Int64)
      @writer = Writer.new(@base)
      @ops    = Array(Op).new
      @status = Status::Open
    end

    def root : Draft
      Draft.new(self, Path.new)
    end

    def value : ::JSON::Any
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

    protected def read(path : Path) : ::JSON::Any?
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
        elsif last.is_a?(Ops::Set) && last.path == op.path && (text = last.value.as_s?)
          @ops[-1] = Ops::Set.new(op.path, ::JSON::Any.new(text + op.text))
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
end
