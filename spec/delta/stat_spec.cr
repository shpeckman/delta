# spec/delta/stat_spec.cr
require "../spec_helper"

describe Delta::Stat do
  it "counts insertions and deletions from an edit list" do
    edits = Delta.diff_lines("a\nb\nc\n", "a\nX\nY\nc\n")
    stat = Delta.stat(edits)
    stat.insertions.should eq 2
    stat.deletions.should eq 1
    stat.total.should eq 3
  end

  it "is zero for identical inputs" do
    stat = Delta.stat("a\nb\n", "a\nb\n")
    stat.total.should eq 0
  end

  it "compares by value" do
    Delta::Stat.new(1, 2).should eq Delta::Stat.new(1, 2)
  end
end
