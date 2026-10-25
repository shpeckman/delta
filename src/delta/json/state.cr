# src/delta/json/state.cr
module Delta::JSON
  record Frame, value : ::JSON::Any, ops : Array(Op), seq : Int64

  class Watch
    enum End
      Stopped
      Retired
      Ended
      Failed
    end

    getter value : ::JSON::Any
    getter seq : Int64

    def initialize(@state : State, @value : ::JSON::Any, @seq : Int64, limit : Int32 = PendingOps::LIMIT)
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

    protected def deliver(value : ::JSON::Any, ops : Array(Op), seq : Int64) : Nil
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
    def initialize(value : ::JSON::Any, @limit : Int32 = PendingOps::LIMIT)
      @tracker = Tracker.new(value)
      @mutex = Sync::Mutex.new
      @watches = Array(Watch).new
      @seq = 0_i64
      @end = nil.as(Watch::End?)
      @error = nil.as(Exception?)
    end

    def value : ::JSON::Any
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

    def replace(value : ::JSON::Any) : Array(Op)
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
        retired = [Ops::Replace.new(::JSON::Any.new(nil))] of Op
        @watches.each &.deliver(::JSON::Any.new(nil), retired, @seq)
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
