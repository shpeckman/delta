# spec/delta/json_spec.cr
require "../spec_helper"

private def doc(source : String) : JSON::Any
  JSON.parse(source)
end

describe Delta::JSON do
  describe ".diff" do
    pairs = [
      { %({"a":1,"b":[1,2,3],"c":"hello"}), %({"a":2,"b":[1,9,2,3],"c":"hello world","d":null}) },
      { %({"a":{"b":{"c":[1,2]}}}), %({"a":{"b":{"c":[2]}}}) },
      { %({"text":"hello world"}), %({"text":"world"}) },
      { %([1,2,3,4,5]), %([1,5]) },
      { %("abc"), %("abcdef") },
      { %({"a":1}), %([1]) },
      { %({"a":[{"x":1},{"x":2}]}), %({"a":[{"x":1},{"x":3}]}) },
    ]

    pairs.each do |(before, after)|
      it "round-trips #{before} -> #{after}" do
        base = doc(before)
        value = doc(after)
        ops = Delta.diff_json(base, value)
        Delta.apply_json(base, ops).should eq value
        base.should eq doc(before)
      end
    end

    it "is empty for equal values" do
      Delta::JSON.diff(doc(%({"a":[1,{"b":"c"}]})), doc(%({"a":[1,{"b":"c"}]}))).should be_empty
    end

    it "emits appends and trims for string growth and shrinkage" do
      Delta::JSON.diff(doc(%({"t":"ab"})), doc(%({"t":"abcd"}))).should eq [Delta::JSON::Ops::Append.new(["t"] of Delta::JSON::Segment, "cd")] of Delta::JSON::Op
      Delta::JSON.diff(doc(%({"t":"abcd"})), doc(%({"t":"cd"}))).should eq [Delta::JSON::Ops::Trim.new(["t"] of Delta::JSON::Segment, 2)] of Delta::JSON::Op
    end
  end

  describe "ops" do
    it "parses what it serializes" do
      ops = Delta::JSON.diff(doc(%({"a":"x","b":[1,2],"c":1})), doc(%({"a":"xy","b":[1,3,2]})))
      Delta::JSON.parse_ops(ops.to_json).should eq ops
    end

    it "rejects malformed ops" do
      expect_raises(Delta::JSON::Errors::InvalidOp) { Delta::JSON.parse_ops(%([["z",[]]])) }
      expect_raises(Delta::JSON::Errors::InvalidOp) { Delta::JSON.parse_ops(%([["s",["a"]]])) }
      expect_raises(Delta::JSON::Errors::InvalidOp) { Delta::JSON.parse_ops(%([["d",[-1]]])) }
      expect_raises(Delta::JSON::Errors::InvalidOp) { Delta::JSON.parse_ops(%([["d",[4294967296]]])) }
    end

    it "rejects invalid paths" do
      expect_raises(Delta::JSON::Errors::InvalidPath) do
        Delta::JSON.apply_immutable(doc(%({"a":1})), Delta::JSON.parse_ops(%([["s",["x","y"],1]])))
      end
    end

    it "leaves the base untouched in immutable mode and shares unchanged subtrees" do
      base = doc(%({"a":{"b":1},"c":{"d":2}}))
      result = Delta::JSON.apply_immutable(base, Delta::JSON.parse_ops(%([["s",["a","b"],5]])))
      base["a"]["b"].should eq 1
      result["a"]["b"].should eq 5
      result["c"].as_h.same?(base["c"].as_h).should be_true
    end
  end

  describe Delta::JSON::Tracker do
    it "records folded ops from a draft" do
      tracker = Delta::JSON::Tracker.new(doc(%({"items":[],"log":""})))
      prepared = tracker.change do |draft|
        draft["items"].push(1, 2, 3)
        draft.append("log", "a")
        draft.append("log", "b")
        draft["items"].reverse
      end
      tracker.value.should eq doc(%({"items":[3,2,1],"log":"ab"}))
      tracker.revision.should eq 1
      Delta::JSON.apply_immutable(prepared.base, prepared.ops).should eq tracker.value
    end

    it "rejects stale preparations" do
      tracker = Delta::JSON::Tracker.new(doc(%({"a":1})))
      change = tracker.begin_change
      change.root["a"] = 2
      tracker.replace(doc(%({"a":3})))
      expect_raises(Delta::JSON::Errors::Stale) { change.prepare }
    end

    it "aborts the change when the block raises" do
      tracker = Delta::JSON::Tracker.new(doc(%({"a":1})))
      expect_raises(Exception, "boom") do
        tracker.change do |draft|
          draft["a"] = 2
          raise "boom"
        end
      end
      tracker.value.should eq doc(%({"a":1}))
    end
  end

  describe Delta::JSON::PendingOps do
    it "coalesces repeated leaf writes and appends" do
      pending = Delta::JSON::PendingOps.new
      pending.push(Delta::JSON.parse_ops(%([["s",["t"],"a"],["s",["n"],1],["a",["t"],"b"],["a",["t"],"c"],["s",["n"],2]])))
      pending.take(doc("null")).should eq Delta::JSON.parse_ops(%([["s",["t"],"abc"],["s",["n"],2]]))
      pending.empty?.should be_true
    end

    it "collapses to a replace on overflow" do
      pending = Delta::JSON::PendingOps.new(2)
      pending.push(Delta::JSON.parse_ops(%([["d",["a"]],["d",["b"]],["d",["c"]]])))
      pending.overflow?.should be_true
      current = doc(%({"z":1}))
      pending.take(current).should eq [Delta::JSON::Ops::Replace.new(current)] of Delta::JSON::Op
    end
  end

  describe Delta::JSON::Wire do
    it "round-trips through the path-interning encoding" do
      encoder = Delta::JSON::Wire::Encoder.new
      decoder = Delta::JSON::Wire::Decoder.new
      first = Delta::JSON.parse_ops(%([["a",["log"],"x"],["s",["n"],1]]))
      second = Delta::JSON.parse_ops(%([["a",["log"],"y"],["r",{"fresh":true}],["s",["n"],2]]))
      frame = encoder.encode(second.tap { decoder.decode(encoder.encode(first)).should eq first })
      frame.should contain(%(["a",0,"y"]))
      decoder.decode(frame).should eq second
    end
  end

  describe Delta::JSON::State do
    it "delivers coalesced frames to watchers" do
      state = Delta::JSON::State.new(doc(%({"log":""})))
      watch = state.watch
      state.change { |draft| draft.append("log", "a") }
      state.change { |draft| draft.append("log", "b") }
      frame = watch.receive?.should_not be_nil
      frame.seq.should eq 2
      frame.value.should eq doc(%({"log":"ab"}))
      frame.ops.should eq Delta::JSON.parse_ops(%([["a",["log"],"ab"]]))
    end

    it "ends watchers on retire and refuses further changes" do
      state = Delta::JSON::State.new(doc(%({"a":1})))
      watch = state.watch
      state.retire
      watch.receive?.should_not be_nil
      watch.receive?.should be_nil
      watch.ended.should eq Delta::JSON::Watch::End::Retired
      expect_raises(Delta::JSON::Errors::Closed) { state.change { |draft| draft["a"] = 2 } }
    end

    it "wakes a blocked receiver from another fiber" do
      state = Delta::JSON::State.new(doc(%({"n":0})))
      watch = state.watch
      done = Channel(Delta::JSON::Frame?).new
      spawn { done.send(watch.receive?) }
      Fiber.yield
      state.change { |draft| draft["n"] = 1 }
      done.receive.try(&.value).should eq doc(%({"n":1}))
      watch.stop
      state.watch_count.should eq 0
    end
  end
end
