# spec/words_spec.cr
require "spec"
require "../src/delta/words"

describe Delta::Words do
  describe ".tokens" do
    it "splits an empty string into no tokens" do
      Delta::Words.tokens("").should eq [] of String
    end

    it "splits words and single spaces" do
      Delta::Words.tokens("hello world").should eq ["hello", " ", "world"]
    end

    it "keeps runs of whitespace together" do
      Delta::Words.tokens("a  b\n").should eq ["a", "  ", "b", "\n"]
    end

    it "handles leading trailing and multiple whitespace" do
      Delta::Words.tokens("  a\tb  ").should eq ["  ", "a", "\t", "b", "  "]
    end

    it "keeps punctuation glued to words" do
      Delta::Words.tokens("foo(bar)").should eq ["foo(bar)"]
    end

    it "treats unicode whitespace as whitespace" do
      Delta::Words.tokens("a\u00A0b").should eq ["a", "\u00A0", "b"]
    end
  end

  describe ".tokens round trip" do
    ["", "hello world", "a  b\n", "  \t ", "foo(bar) baz.", "  leading and trailing  ", "café déjà vu", "a\n\nb", "\r\n"].each do |source|
      it "rejoins tokens for #{source.inspect}" do
        Delta::Words.tokens(source).join.should eq source
      end
    end
  end

  describe ".markup" do
    it "renders equal delete and insert edits" do
      old = ["a", " ", "b"]
      new = ["a", " ", "c"]
      edits = [
        Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 2, 0, 2),
        Delta::Edit.new(Delta::Edit::Kind::Delete, 2, 1, 2, 0),
        Delta::Edit.new(Delta::Edit::Kind::Insert, 2, 0, 2, 1),
      ]
      Delta::Words.markup(old, new, edits).should eq "a [-b-]{+c+}"
    end

    it "does not emit empty delete or insert runs" do
      old = ["a", "b"]
      new = ["a", "b"]
      edits = [
        Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 1, 0, 1),
        Delta::Edit.new(Delta::Edit::Kind::Delete, 1, 0, 1, 0),
        Delta::Edit.new(Delta::Edit::Kind::Insert, 1, 0, 1, 0),
        Delta::Edit.new(Delta::Edit::Kind::Equal, 1, 1, 1, 1),
      ]
      Delta::Words.markup(old, new, edits).should eq "ab"
    end
  end
end
