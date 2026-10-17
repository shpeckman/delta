# spec/delta/compaction_spec.cr
require "../spec_helper"

describe Delta::Compaction do
  it "slides changes to the earliest position without blank lines" do
    old     = "1\n2\n1\n2\n3\n"
    new     = "1\n2\n1\n2\n1\n2\n3\n"
    edits   = Delta.diff_lines(old, new)
    inserts = edits.select(&.kind.insert?)
    inserts.size.should eq 1
    inserts[0].a_pos.should eq 0
    inserts[0].b_len.should eq 2
    Delta.apply(old.lines, new.lines, edits.map { |e|
      e
    }).should eq new.lines
  end

  it "prefers a blank-line boundary over an earlier position" do
    old   = "x\n\n1\ny\n"
    new   = "x\n\n1\n\n1\ny\n"
    edits = Delta.diff_lines(old, new)
    edits.should eq [
      Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 2, 0, 2),
      Delta::Edit.new(Delta::Edit::Kind::Insert, 2, 0, 2, 2),
      Delta::Edit.new(Delta::Edit::Kind::Equal, 2, 2, 4, 2),
    ]
  end

  it "does not shift changes when compact is false" do
    old   = "1\n2\n1\n2\n3\n"
    new   = "1\n2\n1\n2\n1\n2\n3\n"
    edits = Delta.diff_lines(old, new, compact: false)
    Delta.apply(old.lines, new.lines, edits).should eq new.lines
  end

  it "keeps reconstruction valid for random repetitive inputs" do
    rnd = Random.new(5)
    100.times do
      a     = Array.new(rnd.rand(60)) { rnd.rand(3) }
      b     = Array.new(rnd.rand(60)) { rnd.rand(3) }
      edits = Delta.diff(a, b)
      Delta.apply(a, b, edits).should eq b
      plain = Delta.diff(a, b, compact: false)
      Delta.apply(a, b, plain).should eq b
    end
  end

  it "keeps unified diffs valid after compaction" do
    rnd  = Random.new(11)
    pool = (0...8).map { |i| "line #{i}" }
    50.times do
      old   = (0...rnd.rand(50)).map { pool[rnd.rand(pool.size)] }.join("\n") + "\n"
      lines = old.lines
      rnd.rand(8).times do
        if rnd.rand(2) == 0 && !lines.empty?
          lines.delete_at(rnd.rand(lines.size))
        else
          lines.insert(rnd.rand(lines.size + 1), pool[rnd.rand(pool.size)])
        end
      end
      new = lines.join("\n") + (lines.empty? ? "" : "\n")
      next if old == new
      Delta.apply_patch(old, Delta.unified_diff(old, new)).should eq new
    end
  end
end
