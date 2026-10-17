# spec/fuzzy_spec.cr
require "./spec_helper"

describe Delta::Patch do
  describe "fuzzy apply" do
    it "still applies exactly with fuzz: 0" do
      old   = "a\nb\nc\nd\ne\n"
      new   = "a\nb\nX\nd\ne\n"
      patch = Delta.unified_diff(old, new)
      Delta.apply_patch(old, patch).should eq new
    end

    it "tolerates one mismatched context line with fuzz: 1" do
      old   = "a\nb\nc\nd\ne\n"
      new   = "a\nb\nX\nd\ne\n"
      patch = Delta.unified_diff(old, new)
      fuzzy = "a\nbb\nc\nd\ne\n"
      expect_raises(Delta::PatchError) { Delta.apply_patch(fuzzy, patch) }
      Delta.apply_patch(fuzzy, patch, fuzz: 1).should eq "a\nbb\nX\nd\ne\n"
    end

    it "requires the fuzz threshold to cover all mismatches" do
      old   = "a\nb\nc\nd\ne\n"
      new   = "a\nb\nX\nd\ne\n"
      patch = Delta.unified_diff(old, new)
      fuzzy = "a\nbb\nc\ndd\ne\n"
      expect_raises(Delta::PatchError) { Delta.apply_patch(fuzzy, patch, fuzz: 1) }
      Delta.apply_patch(fuzzy, patch, fuzz: 2).should eq "a\nbb\nX\ndd\ne\n"
    end

    it "never fuzzes a deleted line" do
      old     = "a\nb\nc\nd\ne\n"
      new     = "a\nb\nX\nd\ne\n"
      patch   = Delta.unified_diff(old, new)
      corrupt = "a\nb\ncc\nd\ne\n"
      expect_raises(Delta::PatchError) { Delta.apply_patch(corrupt, patch, fuzz: 2) }
    end
  end
end
