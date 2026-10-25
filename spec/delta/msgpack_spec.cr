require "../spec_helper"

describe Delta::Msgpack do
  def t(value : MessagePack::Type) : MessagePack::Type
    value
  end

  it "diffs identical documents to no ops" do
    a = t({"a" => [1_i64, {"b" => "c"}] of MessagePack::Type} of MessagePack::Type => MessagePack::Type)
    Delta::Msgpack.diff(a, Delta::Msgpack.copy(a)).should be_empty
  end

  it "appends and trims strings" do
    base = t({"t" => "ab"} of MessagePack::Type => MessagePack::Type)
    Delta::Msgpack.diff(base, t({"t" => "abcd"} of MessagePack::Type => MessagePack::Type))
      .should eq [Delta::Msgpack::Ops::Append.new(["t"] of Delta::Msgpack::Segment, "cd")] of Delta::Msgpack::Op
    Delta::Msgpack.diff(base, t({"t" => "cd"} of MessagePack::Type => MessagePack::Type))
      .should eq [Delta::Msgpack::Ops::Trim.new(["t"] of Delta::Msgpack::Segment, 2)] of Delta::Msgpack::Op
  end

  it "sets nested edits and splices arrays" do
    base = t({"a" => "x", "b" => [1_i64, 2_i64] of MessagePack::Type, "c" => 1_i64} of MessagePack::Type => MessagePack::Type)
    value = t({"a" => "xy", "b" => [1_i64, 3_i64, 2_i64] of MessagePack::Type} of MessagePack::Type => MessagePack::Type)
    ops = Delta::Msgpack.diff(base, value)
    Delta::Msgpack.apply_immutable(base, ops).should eq value
  end

  it "round trips diff and apply without mutating the base" do
    base = t({"items" => [1_i64, 2_i64, 3_i64] of MessagePack::Type, "log" => ""} of MessagePack::Type => MessagePack::Type)
    original = Delta::Msgpack.copy(base)
    value = t({"items" => [1_i64, 2_i64] of MessagePack::Type, "log" => "hi"} of MessagePack::Type => MessagePack::Type)
    ops = Delta::Msgpack.diff(base, value)
    Delta::Msgpack.apply_immutable(base, ops).should eq value
    base.should eq original
  end

  it "applies in place when asked" do
    base = t({"a" => 1_i64} of MessagePack::Type => MessagePack::Type)
    value = t({"a" => 2_i64} of MessagePack::Type => MessagePack::Type)
    Delta::Msgpack.apply(base, Delta::Msgpack.diff(base, value)).should eq value
  end

  it "supports non-string map keys" do
    base = t({1_i64 => "a"} of MessagePack::Type => MessagePack::Type)
    value = t({1_i64 => "b"} of MessagePack::Type => MessagePack::Type)
    ops = Delta::Msgpack.diff(base, value)
    Delta::Msgpack.apply_immutable(base, ops).should eq value
  end

  it "exposes top-level helpers" do
    base = t({"a" => 1_i64} of MessagePack::Type => MessagePack::Type)
    value = t({"a" => 2_i64} of MessagePack::Type => MessagePack::Type)
    Delta.apply_msgpack(base, Delta.diff_msgpack(base, value)).should eq value
  end
end
