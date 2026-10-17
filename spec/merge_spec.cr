# spec/merge_spec.cr
require "./spec_helper"

describe Delta.merge do
  it "merges cleanly when each side changes different regions" do
    base = "1\n2\n3\n4\n5\n"
    ours = "1\nA\n3\n4\n5\n"
    theirs = "1\n2\n3\nB\n5\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_true
    result.text.should eq "1\nA\n3\nB\n5\n"
  end

  it "takes an identical change from both sides once" do
    base = "1\n2\n3\n"
    ours = "1\nX\n3\n"
    theirs = "1\nX\n3\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_true
    result.text.should eq "1\nX\n3\n"
  end

  it "conflicts when both sides change the same region differently" do
    base = "1\n2\n3\n"
    ours = "1\nA\n3\n"
    theirs = "1\nB\n3\n"
    result = Delta.merge(base, ours, theirs, ours_label: "mine", theirs_label: "yours")
    result.clean?.should be_false
    result.conflicts.should eq 1
    result.text.should eq "1\n<<<<<<< mine\nA\n=======\nB\n>>>>>>> yours\n3\n"
  end

  it "conflicts on abutting changes" do
    base = "1\n2\n3\n4\n"
    ours = "1\nA\n3\n4\n"
    theirs = "1\n2\nB\n4\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_false
  end

  it "conflicts when both sides insert different content at the same point" do
    base = "1\n2\n"
    ours = "1\nA\n2\n"
    theirs = "1\nB\n2\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_false
    result.conflicts.should eq 1
  end

  it "merges identical insertions cleanly" do
    base = "1\n2\n"
    ours = "1\nA\n2\n"
    theirs = "1\nA\n2\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_true
    result.text.should eq "1\nA\n2\n"
  end

  it "handles delete versus keep" do
    base = "1\n2\n3\n"
    ours = "1\n3\n"
    theirs = "1\n2\n3\n4\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_true
    result.text.should eq "1\n3\n4\n"
  end

  it "conflicts on delete versus modify" do
    base = "1\n2\n3\n"
    ours = "1\n3\n"
    theirs = "1\nX\n3\n"
    result = Delta.merge(base, ours, theirs)
    result.clean?.should be_false
  end

  it "preserves content before and after conflict regions" do
    base = "h1\nh2\n1\n2\nf1\nf2\n"
    ours = "h1\nh2\nA\n2\nf1\nf2\n"
    theirs = "h1\nh2\nB\n2\nf1\nf2\n"
    result = Delta.merge(base, ours, theirs)
    result.text.should start_with "h1\nh2\n"
    result.text.should end_with "f1\nf2\n"
  end

  it "merges with no changes on either side" do
    result = Delta.merge("a\nb\n", "a\nb\n", "a\nb\n")
    result.clean?.should be_true
    result.text.should eq "a\nb\n"
  end

  it "works with all algorithms" do
    base = "1\n2\n3\n4\n5\n6\n7\n"
    ours = "1\nA\n3\n4\n5\n6\n7\n"
    theirs = "1\n2\n3\n4\n5\nB\n7\n"
    {Delta::Myers.new, Delta::Histogram.new, Delta::Patience.new}.each do |algorithm|
      result = Delta.merge(base, ours, theirs, algorithm: algorithm)
      result.clean?.should be_true
      result.text.should eq "1\nA\n3\n4\n5\nB\n7\n"
    end
  end
end
