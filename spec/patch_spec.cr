# spec/patch_spec.cr
require "./spec_helper"

describe Delta::Patch do
  it "round-trips a simple change" do
    old   = "a\nb\nc\nd\ne\n"
    new   = "a\nb\nX\nd\ne\n"
    patch = Delta.unified_diff(old, new)
    Delta.apply_patch(old, patch).should eq new
  end

  it "round-trips file headers" do
    old   = "1\n2\n3\n"
    new   = "1\nX\n3\n"
    patch = Delta.unified_diff(old, new, old_path: "a/f.cr", new_path: "b/f.cr")
    files = Delta.parse_patch(patch)
    files.size.should eq 1
    files[0].old_path.should eq "a/f.cr"
    files[0].new_path.should eq "b/f.cr"
    Delta.apply_patch(old, patch).should eq new
  end

  it "round-trips a missing trailing newline" do
    old   = "a\nb"
    new   = "a\nc\n"
    patch = Delta.unified_diff(old, new)
    Delta.apply_patch(old, patch).should eq new
    Delta.apply_patch(new, Delta.unified_diff(new, old)).should eq old
  end

  it "round-trips insertion into and deletion from empty files" do
    Delta.apply_patch("", Delta.unified_diff("", "a\nb\n")).should eq "a\nb\n"
    Delta.apply_patch("a\nb\n", Delta.unified_diff("a\nb\n", "")).should eq ""
  end

  it "tolerates line number drift" do
    old     = "a\nb\nc\nd\ne\nf\ng\nh\n"
    new     = "a\nb\nc\nd\ne\nf\nX\nh\n"
    patch   = Delta.unified_diff(old, new)
    drifted = "p\nq\n" + old
    Delta.apply_patch(drifted, patch).should eq "p\nq\n" + new
  end

  it "raises PatchError when context does not match" do
    old   = "a\nb\nc\n"
    new   = "a\nX\nc\n"
    patch = Delta.unified_diff(old, new)
    expect_raises(Delta::PatchError) { Delta.apply_patch("totally\ndifferent\nfile\n", patch) }
  end

  it "raises PatchError for a patch without hunks" do
    expect_raises(Delta::PatchError, "no hunks") { Delta.apply_patch("a\n", "junk\n") }
  end

  it "round-trips random string pairs through all algorithms" do
    rnd  = Random.new(1234)
    pool = (0...20).map { |i| "line #{i}" }
    {Delta::Myers.new, Delta::Histogram.new, Delta::Patience.new}.each do |algorithm|
      50.times do
        old   = (0...rnd.rand(60)).map { pool[rnd.rand(pool.size)] }.join("\n") + "\n"
        lines = old.lines
        rnd.rand(10).times do
          case rnd.rand(3)
          when 0 then lines.delete_at(rnd.rand(lines.size)) unless lines.empty?
          when 1 then lines.insert(rnd.rand(lines.size + 1), pool[rnd.rand(pool.size)])
          else        lines[rnd.rand(lines.size)] = pool[rnd.rand(pool.size)] unless lines.empty?
          end
        end
        new = lines.join("\n") + (lines.empty? ? "" : "\n")
        next if old == new
        patch = Delta.unified_diff(old, new, algorithm: algorithm)
        Delta.apply_patch(old, patch).should eq new
      end
    end
  end
end
