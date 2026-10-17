# spec/patience_spec.cr
require "./spec_helper"

describe Delta::Patience do
  it "returns no edits for empty inputs" do
    Delta.diff([] of Int32, [] of Int32, Delta::Patience.new).should eq [] of Delta::Edit
  end

  it "returns a single equal op for identical inputs" do
    edits = Delta.diff([1, 2, 3], [1, 2, 3], Delta::Patience.new)
    edits.should eq [Delta::Edit.new(Delta::Kind::Equal, 0, 3, 0, 3)]
  end

  it "handles disjoint sequences" do
    a     = [1, 2, 3]
    b     = [4, 5, 6]
    edits = Delta.diff(a, b, Delta::Patience.new)
    Delta.apply(a, b, edits).should eq b
  end

  it "anchors on unique lines around moved blocks" do
    a     = [1, 2, 3, 4, 5, 6]
    b     = [4, 5, 6, 1, 2, 3]
    edits = Delta.diff(a, b, Delta::Patience.new)
    Delta.apply(a, b, edits).should eq b
    edits.count(&.kind.equal?).should be >= 1
  end

  it "falls back to myers when there are no unique anchors" do
    a     = [1, 1, 2, 2]
    b     = [2, 2, 1, 1]
    edits = Delta.diff(a, b, Delta::Patience.new)
    Delta.apply(a, b, edits).should eq b
  end

  it "reconstructs b for random sequences" do
    rnd = Random.new(9)
    100.times do
      a     = Array.new(rnd.rand(80)) { rnd.rand(10) }
      b     = Array.new(rnd.rand(80)) { rnd.rand(10) }
      edits = Delta.diff(a, b, Delta::Patience.new)
      Delta.apply(a, b, edits).should eq b
    end
  end
end
