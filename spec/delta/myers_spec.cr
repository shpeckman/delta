# spec/delta/myers_spec.cr
require "../spec_helper"

describe Delta::Myers do
  it "returns no edits for empty inputs" do
    Delta.diff([] of Int32, [] of Int32).should eq [] of Delta::Edit
  end

  it "returns a single equal op for identical inputs" do
    edits = Delta.diff([1, 2, 3], [1, 2, 3])
    edits.should eq [Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 3, 0, 3)]
  end

  it "inserts into an empty input" do
    edits = Delta.diff([] of Int32, [1, 2])
    edits.should eq [Delta::Edit.new(Delta::Edit::Kind::Insert, 0, 0, 0, 2)]
  end

  it "deletes everything" do
    edits = Delta.diff([1, 2], [] of Int32)
    edits.should eq [Delta::Edit.new(Delta::Edit::Kind::Delete, 0, 2, 0, 0)]
  end

  it "produces a minimal diff for the Myers paper example" do
    a       = "ABCABBA".chars
    b       = "CBABAC".chars
    edits   = Delta.diff(a, b)
    changes = edits.reject(&.kind.equal?).sum { |e| e.a_len + e.b_len }
    changes.should eq 5
    Delta.apply(a, b, edits).should eq b
  end

  it "handles disjoint sequences" do
    a     = [1, 2, 3]
    b     = [4, 5, 6]
    edits = Delta.diff(a, b)
    Delta.apply(a, b, edits).should eq b
  end

  it "reconstructs b for random sequences" do
    rnd = Random.new(42)
    100.times do
      a     = Array.new(rnd.rand(50)) { rnd.rand(10) }
      b     = Array.new(rnd.rand(50)) { rnd.rand(10) }
      edits = Delta.diff(a, b)
      Delta.apply(a, b, edits).should eq b
    end
  end
end
