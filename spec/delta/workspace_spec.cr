# spec/workspace_spec.cr
require "../spec_helper"

describe Delta::Workspace do
  it "produces the same edits with and without a workspace" do
    ws  = Delta::Workspace.new
    rnd = Random.new(21)
    {Delta::Myers.new, Delta::Histogram.new, Delta::Patience.new}.each do |algorithm|
      50.times do
        a       = Array.new(rnd.rand(60)) { rnd.rand(4) }
        b       = Array.new(rnd.rand(60)) { rnd.rand(4) }
        with_ws = Delta.diff(a, b, algorithm, workspace: ws)
        without = Delta.diff(a, b, algorithm)
        with_ws.should eq without
      end
    end
  end

  it "reuses buffers across growing input sizes" do
    ws  = Delta::Workspace.new
    rnd = Random.new(31)
    100.times do
      a     = Array.new(rnd.rand(500)) { rnd.rand(10) }
      b     = Array.new(rnd.rand(500)) { rnd.rand(10) }
      edits = Delta.diff(a, b, workspace: ws)
      Delta.apply(a, b, edits).should eq b
    end
  end

  it "works for line diffs and unified diffs" do
    ws  = Delta::Workspace.new
    old = (1..200).map(&.to_s).join("\n") + "\n"
    new = (1..200).map { |i| i == 50 ? "X" : i.to_s }.join("\n") + "\n"
    Delta.diff_lines(old, new, workspace: ws).should eq Delta.diff_lines(old, new)
    Delta.unified_diff(old, new, workspace: ws).should eq Delta.unified_diff(old, new)
  end

  it "can be reused across algorithms" do
    ws = Delta::Workspace.new
    a  = (1..100).map { |i| i % 7 }
    b  = a.dup
    b.delete_at(10)
    b.insert(30, 99)
    {Delta::Myers.new, Delta::Histogram.new, Delta::Patience.new}.each do |algorithm|
      edits = Delta.diff(a, b, algorithm, workspace: ws)
      Delta.apply(a, b, edits).should eq b
    end
  end
end
