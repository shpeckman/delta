# spec/unified_spec.cr
require "./spec_helper"

describe Delta.unified_diff do
  it "returns an empty string for identical inputs" do
    Delta.unified_diff("a\nb\n", "a\nb\n").should eq ""
  end

  it "renders a single hunk with headers" do
    old = "a\nb\nc\nd\ne\nf\ng\n"
    new = "a\nb\nX\nd\ne\nf\ng\n"
    Delta.unified_diff(old, new, context: 1, old_path: "a/f", new_path: "b/f").should eq <<-DIFF
      --- a/f
      +++ b/f
      @@ -2,3 +2,3 @@
       b
      -c
      +X
       d
      DIFF
  end

  it "splits distant changes into separate hunks" do
    old = (1..20).map(&.to_s).join("\n") + "\n"
    new_lines = (1..20).map(&.to_s)
    new_lines[2] = "X"
    new_lines[17] = "Y"
    new = new_lines.join("\n") + "\n"
    patch = Delta.unified_diff(old, new, context: 2)
    patch.scan(/@@ /).size.should eq 4
    patch.should contain "@@ -1,5 +1,5 @@"
    patch.should contain "@@ -16,5 +16,5 @@"
  end

  it "merges nearby changes into one hunk" do
    old = "1\n2\n3\n4\n5\n"
    new = "1\nX\n3\nY\n5\n"
    patch = Delta.unified_diff(old, new, context: 2)
    patch.scan(/@@ /).size.should eq 2
  end

  it "marks a missing trailing newline" do
    patch = Delta.unified_diff("a\nb", "a\nc")
    patch.should eq <<-DIFF
      @@ -1,2 +1,2 @@
       a
      -b
      \\ No newline at end of file
      +c
      \\ No newline at end of file
      DIFF
  end

  it "handles insertion into an empty file" do
    patch = Delta.unified_diff("", "a\n")
    patch.should eq "@@ -0,0 +1 @@\n+a\n"
  end

  it "handles deletion of everything" do
    patch = Delta.unified_diff("a\n", "")
    patch.should eq "@@ -1 +0,0 @@\n-a\n"
  end

  it "omits file headers when no paths are given" do
    Delta.unified_diff("a\n", "b\n").should_not contain "---"
  end
end
