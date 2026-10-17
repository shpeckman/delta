# spec/delta_spec.cr
require "../spec_helper"

describe Delta do
  it "has a version" do
    Delta::VERSION.should_not be_empty
  end

  describe ".diff_lines" do
    it "returns no edits for empty inputs" do
      Delta.diff_lines("", "").should eq [] of Delta::Edit
    end

    it "returns no edits for identical inputs" do
      Delta.diff_lines("a\nb\n", "a\nb\n").should eq [
        Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 2, 0, 2),
      ]
    end

    it "treats a missing trailing newline as a change on the last line" do
      edits = Delta.diff_lines("a\nb\n", "a\nb")
      edits.should_not eq [Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 2, 0, 2)]
    end

    it "handles CRLF line endings" do
      old   = "a\r\nb\r\n"
      new   = "a\r\nX\r\n"
      edits = Delta.diff_lines(old, new)
      la, lb = Delta::Tokenizer.lines(old, new)
      old_lines = (0...la.size).map { |i| String.new(la.line_at(i)) }
      new_lines = (0...lb.size).map { |i| String.new(lb.line_at(i)) }
      Delta.apply(old_lines, new_lines, edits).should eq new_lines
    end

    it "round-trips random line-based diffs through all algorithms" do
      rnd  = Random.new(99)
      pool = (0...30).map { |i| "line #{i}" }
      {Delta::Myers.new, Delta::Histogram.new, Delta::Patience.new}.each do |algorithm|
        50.times do
          a = (0...rnd.rand(80)).map { pool[rnd.rand(pool.size)] }
          b = a.dup
          rnd.rand(12).times do
            case rnd.rand(3)
            when 0 then b.delete_at(rnd.rand(b.size)) unless b.empty?
            when 1 then b.insert(rnd.rand(b.size + 1), pool[rnd.rand(pool.size)])
            else        b[rnd.rand(b.size)] = pool[rnd.rand(pool.size)] unless b.empty?
            end
          end
          edits = Delta.diff_lines(a.join("\n"), b.join("\n"), algorithm: algorithm)
          Delta.apply(a, b, edits).should eq b
        end
      end
    end
  end

  describe ".diff" do
    it "works on generic sequences" do
      edits = Delta.diff([1, 2, 3], [1, 4, 3])
      Delta.apply([1, 2, 3], [1, 4, 3], edits).should eq [1, 4, 3]
    end

    it "works on strings as element sequences" do
      edits = Delta.diff(%w(a b c), %w(a x c))
      Delta.apply(%w(a b c), %w(a x c), edits).should eq %w(a x c)
    end
  end
end
