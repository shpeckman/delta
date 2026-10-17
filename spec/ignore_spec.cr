# spec/ignore_spec.cr
require "./spec_helper"

describe Delta do
  describe "ignore options" do
    it "treats case-only differences as equal with ignore_case" do
      Delta.diff_lines("Foo\n", "foo\n", ignore_case: true).should eq [
        Delta::Edit.new(Delta::Kind::Equal, 0, 1, 0, 1),
      ]
    end

    it "still detects real changes with ignore_case" do
      edits = Delta.diff_lines("Foo\n", "bar\n", ignore_case: true)
      edits.any?(&.kind.delete?).should be_true
      edits.any?(&.kind.insert?).should be_true
    end

    it "ignores all whitespace with Whitespace::All" do
      Delta.diff_lines("a b\n", "ab\n", whitespace: Delta::Whitespace::All).should eq [
        Delta::Edit.new(Delta::Kind::Equal, 0, 1, 0, 1),
      ]
      Delta.diff_lines("a  b\n", "a b\n", whitespace: Delta::Whitespace::All).should eq [
        Delta::Edit.new(Delta::Kind::Equal, 0, 1, 0, 1),
      ]
    end

    it "ignores whitespace amount but not presence with Whitespace::Amount" do
      Delta.diff_lines("a  b\n", "a b\n", whitespace: Delta::Whitespace::Amount).should eq [
        Delta::Edit.new(Delta::Kind::Equal, 0, 1, 0, 1),
      ]
      edits = Delta.diff_lines("a b\n", "ab\n", whitespace: Delta::Whitespace::Amount)
      edits.any?(&.kind.delete?).should be_true
    end

    it "keeps the trailing newline distinct under whitespace ignore" do
      edits = Delta.diff_lines("a\n", "a", whitespace: Delta::Whitespace::All)
      edits.should_not eq [Delta::Edit.new(Delta::Kind::Equal, 0, 1, 0, 1)]
    end

    it "renders nothing for whitespace-only diffs" do
      Delta.unified_diff("a  b\nc\n", "a b\nc\n", whitespace: Delta::Whitespace::All).should eq ""
    end

    it "keeps reconstruction valid with ignore options" do
      old   = "Foo bar\nbaz  qux\nend\n"
      new   = "foo  bar\nbaz qux\nend\n"
      edits = Delta.diff_lines(old, new, whitespace: Delta::Whitespace::All, ignore_case: true)
      edits.should eq [Delta::Edit.new(Delta::Kind::Equal, 0, 3, 0, 3)]
    end
  end
end
