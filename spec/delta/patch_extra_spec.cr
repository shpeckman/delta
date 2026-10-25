# spec/delta/patch_extra_spec.cr
require "spec"
require "file_utils"
require "../../src/delta/patch"

private def with_tmpdir(&block : String ->)
  path = File.tempname("delta-spec-")
  Dir.mkdir(path)
  begin
    yield path
  ensure
    FileUtils.rm_rf(path)
  end
end

describe Delta::Patch do
  it "reverses a one-hunk patch" do
    patch = "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new\n"
    reversed = "--- b/f\n+++ a/f\n@@ -1 +1 @@\n+old\n-new\n"
    Delta::Patch.reverse(patch).should eq reversed
    Delta::Patch.apply("new\n", reversed).should eq "old\n"
    Delta::Patch.apply("new\n", patch, reverse: true).should eq "old\n"
    Delta::Patch.apply("old\n", patch).should eq "new\n"
  end

  it "round-trips render(parse(...))" do
    patch = "--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n\\ No newline at end of file\n"
    Delta::Patch.render(Delta::Patch.parse(patch)).should eq patch
  end

  it "applies a multi-file patch to a directory" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "x.txt"), "a\nb\n")
      File.write(File.join(dir, "y.txt"), "p\nq\n")
      patch = "--- a/x.txt\n+++ b/x.txt\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n--- a/y.txt\n+++ b/y.txt\n@@ -1,2 +1,2 @@\n-p\n+r\n q\n"
      paths = Delta::Patch.apply_to_dir(patch, dir, strip: 1)
      paths.should eq ["x.txt", "y.txt"]
      File.read(File.join(dir, "x.txt")).should eq "a\nc\n"
      File.read(File.join(dir, "y.txt")).should eq "r\nq\n"
    end
  end

  it "honours strip: 0" do
    with_tmpdir do |dir|
      patch = "--- /dev/null\n+++ a/x.txt\n@@ -0,0 +1 @@\n+x\n"
      paths = Delta::Patch.apply_to_dir(patch, dir, strip: 0)
      paths.should eq ["a/x.txt"]
      File.read(File.join(dir, "a/x.txt")).should eq "x\n"
    end
  end

  it "creates files and parent directories" do
    with_tmpdir do |dir|
      patch = "--- /dev/null\n+++ a/sub/n.txt\n@@ -0,0 +1 @@\n+hello\n"
      paths = Delta::Patch.apply_to_dir(patch, dir, strip: 1)
      paths.should eq ["sub/n.txt"]
      File.read(File.join(dir, "sub/n.txt")).should eq "hello\n"
    end
  end

  it "deletes files" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "m.txt"), "bye\n")
      patch = "--- a/m.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-bye\n"
      paths = Delta::Patch.apply_to_dir(patch, dir, strip: 1)
      paths.should eq ["m.txt"]
      File.exists?(File.join(dir, "m.txt")).should be_false
    end
  end

  it "rejects a deletion that leaves content" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "m.txt"), "bye\nmore\n")
      patch = "--- a/m.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-bye\n"
      expect_raises(Delta::Patch::Error) { Delta::Patch.apply_to_dir(patch, dir, strip: 1) }
      File.read(File.join(dir, "m.txt")).should eq "bye\nmore\n"
    end
  end

  it "rejects path traversal" do
    with_tmpdir do |dir|
      patch = "--- /dev/null\n+++ a/../evil\n@@ -0,0 +1 @@\n+x\n"
      expect_raises(Delta::Patch::Error) { Delta::Patch.apply_to_dir(patch, dir, strip: 1) }
      Dir.children(dir).should be_empty
    end
  end

  it "rejects absolute paths" do
    with_tmpdir do |dir|
      patch = "--- /dev/null\n+++ /etc/evil\n@@ -0,0 +1 @@\n+x\n"
      expect_raises(Delta::Patch::Error) { Delta::Patch.apply_to_dir(patch, dir, strip: 1) }
      Dir.children(dir).should be_empty
    end
  end

  it "applies all-or-nothing across files" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "one.txt"), "old1\n")
      patch = "--- a/one.txt\n+++ b/one.txt\n@@ -1 +1 @@\n-old1\n+new1\n--- a/missing.txt\n+++ b/missing.txt\n@@ -1 +1 @@\n-old2\n+new2\n"
      expect_raises(Delta::Patch::Error) { Delta::Patch.apply_to_dir(patch, dir, strip: 1) }
      File.read(File.join(dir, "one.txt")).should eq "old1\n"
    end
  end
end
