# spec/edit_format_spec.cr
require "./spec_helper"
require "file_utils"

private def with_tempdir(&)
  dir = File.join(Dir.tempdir, "delta_edit_#{Random.rand(1_000_000_000)}")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe Delta::EditFormat do
  it "parses and applies a whole-file edit" do
    text  = "foo.py\n```\nimport sys\nprint(1)\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].kind.should eq Delta::EditFormat::Kind::Whole
    edits[0].path.should eq "foo.py"
    edits[0].content.should eq "import sys\nprint(1)\n"
    Delta.apply_edit("old", edits[0]).should eq "import sys\nprint(1)\n"
  end

  it "normalizes whole-file filenames" do
    { {"**foo.py**", "foo.py"}, {"foo.py:", "foo.py"}, {"# foo.py", "foo.py"} }.each do |(given, want)|
      Delta.parse_edits("#{given}\n```\nx\n```\n")[0].path.should eq want
    end
  end

  it "raises when a whole block has no filename" do
    expect_raises(Delta::EditFormatError, "no filename") do
      Delta.parse_edits("```\nx\n```\n")
    end
  end

  it "parses and applies a SEARCH/REPLACE block" do
    text  = "app.py\n```\n<<<<<<< SEARCH\nfrom flask import Flask\n=======\nimport math\nfrom flask import Flask\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].kind.should eq Delta::EditFormat::Kind::Replace
    edits[0].path.should eq "app.py"
    edits[0].blocks.size.should eq 1
    edits[0].blocks[0].search.should eq "from flask import Flask\n"
    edits[0].blocks[0].replace.should eq "import math\nfrom flask import Flask\n"
    Delta.apply_edit("from flask import Flask\napp.run()\n", edits[0])
      .should eq "import math\nfrom flask import Flask\napp.run()\n"
  end

  it "groups multiple SEARCH/REPLACE blocks under one filename" do
    text  = "app.py\n```\n<<<<<<< SEARCH\na\n=======\nb\n>>>>>>> REPLACE\n<<<<<<< SEARCH\nc\n=======\nd\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].path.should eq "app.py"
    edits[0].blocks.size.should eq 2
    Delta.apply_edit("a\nc\n", edits[0]).should eq "b\nd\n"
  end

  it "appends when SEARCH is empty" do
    text  = "app.py\n```\n<<<<<<< SEARCH\n=======\nnew line\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    Delta.apply_edit("existing\n", edits[0]).should eq "existing\nnew line\n"
  end

  it "tolerates leading-whitespace mismatch" do
    text  = "app.py\n```\n<<<<<<< SEARCH\nprint(1)\n=======\nprint(2)\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    Delta.apply_edit("def f():\n    print(1)\n", edits[0]).should eq "def f():\n    print(2)\n"
  end

  it "applies edits with ... elision" do
    text  = "app.py\n```\n<<<<<<< SEARCH\ndef a():\n    ...\n    return 1\n=======\ndef a():\n    ...\n    return 2\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    Delta.apply_edit("def a():\n    x = 1\n    y = 2\n    return 1\n", edits[0])
      .should eq "def a():\n    x = 1\n    y = 2\n    return 2\n"
  end

  it "raises when a SEARCH block does not match" do
    text  = "app.py\n```\n<<<<<<< SEARCH\nmissing\n=======\nx\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    expect_raises(Delta::EditFormatError, "failed to match") do
      Delta.apply_edit("nothing here\n", edits[0])
    end
  end

  it "parses diff-fenced with the filename on the fence line" do
    text  = "```app.py\n<<<<<<< SEARCH\na\n=======\nb\n>>>>>>> REPLACE\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].path.should eq "app.py"
  end

  it "parses and applies a udiff hunk" do
    text  = "```diff\n--- a/f.py\n+++ b/f.py\n@@ -1,2 +1,2 @@\n-a\n+b\n c\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].kind.should eq Delta::EditFormat::Kind::Unified
    edits[0].path.should eq "f.py"
    Delta.apply_edit("a\nc\n", edits[0]).should eq "b\nc\n"
  end

  it "applies multiple udiff hunks" do
    text  = "```diff\n--- a/f.py\n+++ b/f.py\n@@ -1,1 +1,1 @@\n-a\n+X\n@@ -3,1 +3,1 @@\n-c\n+Z\n```\n"
    edits = Delta.parse_edits(text)
    edits.size.should eq 1
    edits[0].blocks.size.should eq 2
    Delta.apply_edit("a\nb\nc\n", edits[0]).should eq "X\nb\nZ\n"
  end

  it "creates a file from a /dev/null udiff" do
    text  = "```diff\n--- /dev/null\n+++ b/new.py\n@@ -0,0 +1,1 @@\n+hello\n```\n"
    edits = Delta.parse_edits(text)
    edits[0].path.should eq "new.py"
    Delta.apply_edit("", edits[0]).should eq "hello\n"
  end

  it "tolerates wrong udiff line numbers" do
    text  = "```diff\n--- a/f.py\n+++ b/f.py\n@@ -999,1 +999,1 @@\n-a\n+b\n```\n"
    edits = Delta.parse_edits(text)
    Delta.apply_edit("x\na\ny\n", edits[0]).should eq "x\nb\ny\n"
  end

  it "round-trips a unified diff through the udiff format" do
    old   = "a\nb\nc\nd\n"
    new   = "a\nX\nc\nd\n"
    patch = Delta.unified_diff(old, new, old_path: "a/f", new_path: "b/f")
    text  = "```diff\n" + patch + "```\n"
    edits = Delta.parse_edits(text)
    edits[0].path.should eq "f"
    Delta.apply_edit(old, edits[0]).should eq new
  end

  it "does not parse merge-conflict markers as edit blocks" do
    Delta.parse_edits("<<<<<<< HEAD\nold\n=======\nnew\n>>>>>>> branch\n").should be_empty
  end

  it "applies edits to a directory" do
    with_tempdir do |dir|
      File.write(File.join(dir, "f.py"), "a\nb\nc\n")
      text = "```diff\n--- a/f.py\n+++ b/f.py\n@@ -1,1 +1,1 @@\n-a\n+X\n```\n"
      Delta.apply_edits(text, dir).should eq ["f.py"]
      File.read(File.join(dir, "f.py")).should eq "X\nb\nc\n"
    end
  end

  it "writes nothing when one edit fails" do
    with_tempdir do |dir|
      File.write(File.join(dir, "f.py"), "a\nb\nc\n")
      text = "```diff\n--- a/f.py\n+++ b/f.py\n@@ -1,1 +1,1 @@\n-a\n+X\n@@ -9,1 +9,1 @@\n-missing\n+Y\n```\n"
      expect_raises(Delta::EditFormatError) do
        Delta.apply_edits(text, dir)
      end
      File.read(File.join(dir, "f.py")).should eq "a\nb\nc\n"
    end
  end

  it "creates a new file with parent directories" do
    with_tempdir do |dir|
      text = "```diff\n--- /dev/null\n+++ b/sub/new.py\n@@ -0,0 +1,1 @@\n+hello\n```\n"
      Delta.apply_edits(text, dir).should eq ["sub/new.py"]
      File.read(File.join(dir, "sub", "new.py")).should eq "hello\n"
    end
  end

  it "rejects path traversal" do
    expect_raises(Delta::EditFormatError, "traversal") do
      Delta.apply_edits("```diff\n--- a/../x\n+++ b/../x\n@@ -1,1 +1,1 @@\n-a\n+b\n```\n", Dir.tempdir)
    end
  end

  it "rejects absolute paths" do
    expect_raises(Delta::EditFormatError, "absolute") do
      Delta.apply_edits("```diff\n--- /x\n+++ /x\n@@ -1,1 +1,1 @@\n-a\n+b\n```\n", Dir.tempdir)
    end
  end

  it "render_whole round-trips" do
    edits = Delta.parse_edits(Delta.render_whole("f.py", "a\nb\n"))
    edits[0].path.should eq "f.py"
    Delta.apply_edit("ignored", edits[0]).should eq "a\nb\n"
  end

  it "render_whole normalizes a missing trailing newline" do
    edits = Delta.parse_edits(Delta.render_whole("f.py", "abc"))
    Delta.apply_edit("", edits[0]).should eq "abc\n"
  end

  it "render_udiff round-trips" do
    old   = "a\nb\nc\nd\n"
    new   = "a\nX\nc\nd\n"
    edits = Delta.parse_edits(Delta.render_udiff(old, new, "a/f", "b/f"))
    edits[0].path.should eq "f"
    Delta.apply_edit(old, edits[0]).should eq new
  end

  it "render_udiff returns empty for no change" do
    Delta.render_udiff("a\n", "a\n", "a/f", "b/f").should eq ""
  end

  it "render_replace round-trips a single change" do
    old   = "a\nb\nc\nd\ne\nf\n"
    new   = "a\nb\nX\nc\nd\ne\nf\n"
    edits = Delta.parse_edits(Delta.render_replace(old, new, "f.py"))
    edits[0].path.should eq "f.py"
    Delta.apply_edit(old, edits[0]).should eq new
  end

  it "render_replace round-trips multiple changes" do
    old   = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"
    new   = "1\nX\n3\n4\n5\n6\n7\n8\n9\nZ\n"
    edits = Delta.parse_edits(Delta.render_replace(old, new, "f.py"))
    edits[0].blocks.size.should eq 2
    Delta.apply_edit(old, edits[0]).should eq new
  end

  it "render_replace handles whole-file create and delete" do
    create = Delta.parse_edits(Delta.render_replace("", "a\nb\n", "f.py"))
    Delta.apply_edit("", create[0]).should eq "a\nb\n"

    delete = Delta.parse_edits(Delta.render_replace("a\nb\n", "", "f.py"))
    Delta.apply_edit("a\nb\n", delete[0]).should eq ""
  end

  it "render_replace returns empty for no change" do
    Delta.render_replace("a\n", "a\n", "f.py").should eq ""
  end

  it "fuzzy fallback applies a near-miss SEARCH block" do
    src     = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    search  = "l1\nl2\nCHANGED\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    replace = "l1\nl2\nNEW\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    text    = "f.py\n```\n<<<<<<< SEARCH\n" + search + "=======\n" + replace + ">>>>>>> REPLACE\n```\n"
    edits   = Delta.parse_edits(text)
    expect_raises(Delta::EditFormatError) { Delta.apply_edit(src, edits[0]) }
    Delta.apply_edit(src, edits[0], fuzzy: true).should eq replace
  end

  it "fuzzy fallback respects the threshold" do
    src     = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    search  = "l1\nl2\nCHANGED\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    replace = "l1\nl2\nNEW\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n"
    text    = "f.py\n```\n<<<<<<< SEARCH\n" + search + "=======\n" + replace + ">>>>>>> REPLACE\n```\n"
    edits   = Delta.parse_edits(text)
    expect_raises(Delta::EditFormatError) { Delta.apply_edit(src, edits[0], fuzzy: true, threshold: 0.95) }
    Delta.apply_edit(src, edits[0], fuzzy: true, threshold: 0.85).should eq replace
  end
end
