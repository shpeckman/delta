# spec/delta/edit_spec.cr
require "../spec_helper"

describe Delta::Edit do
  it "compares by value" do
    Delta::Edit.new(Delta::Edit::Kind::Delete, 1, 2, 3, 0).should eq Delta::Edit.new(Delta::Edit::Kind::Delete, 1, 2, 3, 0)
    Delta::Edit.new(Delta::Edit::Kind::Delete, 1, 2, 3, 0).should_not eq Delta::Edit.new(Delta::Edit::Kind::Insert, 1, 2, 3, 0)
  end

  it "renders readably" do
    Delta::Edit.new(Delta::Edit::Kind::Equal, 0, 3, 0, 3).to_s.should eq "Equal a[0, 3] b[0, 3]"
  end
end
