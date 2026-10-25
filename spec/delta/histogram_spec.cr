# spec/delta/histogram_spec.cr
require "../spec_helper"

describe Delta::Histogram do
  it "returns no edits for empty inputs" do
    Delta.diff([] of Int32, [] of Int32, Delta::Histogram.new).should eq [] of Delta::Edit
  end

  it "returns a single equal op for identical inputs" do
    edits = Delta.diff([1, 2, 3], [1, 2, 3], Delta::Histogram.new)
    edits.should eq [Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 3, 0, 3)]
  end

  it "handles disjoint sequences" do
    a = [1, 2, 3]
    b = [4, 5, 6]
    edits = Delta.diff(a, b, Delta::Histogram.new)
    Delta.apply(a, b, edits).should eq b
  end

  it "reconstructs b for random sequences with heavy repetition" do
    rnd = Random.new(7)
    100.times do
      a = Array.new(rnd.rand(80)) { rnd.rand(4) }
      b = Array.new(rnd.rand(80)) { rnd.rand(4) }
      edits = Delta.diff(a, b, Delta::Histogram.new)
      Delta.apply(a, b, edits).should eq b
    end
  end

  it "falls back to myers when every element is too common" do
    a = [1] * 100
    b = [1] * 50
    edits = Delta.diff(a, b, Delta::Histogram.new)
    Delta.apply(a, b, edits).should eq b
  end
end
