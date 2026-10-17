# src/delta.cr
require "./delta/edit"
require "./delta/tokenizer"
require "./delta/whitespace"
require "./delta/workspace"
require "./delta/algorithm"
require "./delta/myers"
require "./delta/histogram"
require "./delta/patience"
require "./delta/compaction"
require "./delta/stat"
require "./delta/hunk"
require "./delta/unified"
require "./delta/patch"
require "./delta/edit_format"
require "./delta/merge"
require "./delta/words"

module Delta
  VERSION = {{ `shards version "#{__DIR__}/.."`.chomp.stringify }}

  def self.diff(a : Indexable(T), b : Indexable(T), algorithm : Algorithm = Myers.new, *,
                compact   : Bool       = true,
                workspace : Workspace? = nil) : Array(Edit) forall T
    ta, tb = Tokenizer.tokenize(a, b)
    edits = algorithm.diff(ta, tb, workspace)
    if compact
      blank = nil
      workspace ? Compaction.compact(edits, ta, tb, blank, workspace.compacted, workspace.groups) : Compaction.compact(edits, ta, tb, blank)
    else
      edits
    end
  end

  def self.diff_lines(old_source : String, new_source : String, algorithm : Algorithm = Myers.new, *,
                      compact     : Bool       = true,
                      whitespace  : Whitespace = Whitespace::None,
                      ignore_case : Bool       = false,
                      workspace   : Workspace? = nil) : Array(Edit)
    la, lb = Tokenizer.lines(old_source, new_source, whitespace: whitespace, ignore_case: ignore_case)
    edits = algorithm.diff(la.tokens, lb.tokens, workspace)
    if compact
      blank = la.blank_token || lb.blank_token
      workspace ? Compaction.compact(edits, la.tokens, lb.tokens, blank, workspace.compacted, workspace.groups) : Compaction.compact(edits, la.tokens, lb.tokens, blank)
    else
      edits
    end
  end

  def self.diff_words(old_source : String, new_source : String, algorithm : Algorithm = Myers.new) : Array(Edit)
    diff(Words.tokens(old_source), Words.tokens(new_source), algorithm)
  end

  def self.diff_chars(old_source : String, new_source : String, algorithm : Algorithm = Myers.new) : Array(Edit)
    diff(old_source.chars, new_source.chars, algorithm)
  end

  def self.word_diff(old_source : String, new_source : String, algorithm : Algorithm = Myers.new) : String
    old_tokens = Words.tokens(old_source)
    new_tokens = Words.tokens(new_source)
    Words.markup(old_tokens, new_tokens, diff(old_tokens, new_tokens, algorithm))
  end

  def self.unified_diff(old_source : String, new_source : String, *,
                        context     : Int32      = 3,
                        old_path    : String?    = nil,
                        new_path    : String?    = nil,
                        algorithm   : Algorithm  = Myers.new,
                        compact     : Bool       = true,
                        whitespace  : Whitespace = Whitespace::None,
                        ignore_case : Bool       = false,
                        workspace   : Workspace? = nil) : String
    la, lb = Tokenizer.lines(old_source, new_source, whitespace: whitespace, ignore_case: ignore_case)
    edits = algorithm.diff(la.tokens, lb.tokens, workspace)
    if compact
      blank = la.blank_token || lb.blank_token
      edits = workspace ? Compaction.compact(edits, la.tokens, lb.tokens, blank, workspace.compacted, workspace.groups) : Compaction.compact(edits, la.tokens, lb.tokens, blank)
    end
    hunks = Hunk.build(edits, context)
    Unified.render(la, lb, hunks, old_path, new_path)
  end

  def self.apply_patch(source : String, patch : String, *, reverse : Bool = false, fuzz : Int32 = 0) : String
    Patch.apply(source, patch, reverse: reverse, fuzz: fuzz)
  end

  def self.reverse_patch(patch : String) : String
    Patch.reverse(patch)
  end

  def self.apply_patch_to_dir(patch : String, root : String, *, strip : Int32 = 1, fuzz : Int32 = 0) : Array(String)
    Patch.apply_to_dir(patch, root, strip: strip, fuzz: fuzz)
  end

  def self.parse_patch(patch : String) : Array(Patch::FilePatch)
    Patch.parse(patch)
  end

  def self.parse_edits(text : String, valid_files : Array(String)? = nil) : Array(EditFormat::FileEdit)
    EditFormat.parse(text, valid_files)
  end

  def self.apply_edit(source : String, edit : EditFormat::FileEdit, *, fuzzy : Bool = false, threshold : Float64 = 0.8) : String
    EditFormat.apply_file(source, edit, fuzzy: fuzzy, threshold: threshold)
  end

  def self.apply_edits(text : String, root : String, *, fuzzy : Bool = false, threshold : Float64 = 0.8) : Array(String)
    EditFormat.apply(text, root, fuzzy: fuzzy, threshold: threshold)
  end

  def self.render_whole(path : String, content : String) : String
    EditFormat.render_whole(path, content)
  end

  def self.render_udiff(old : String, new : String, old_path : String, new_path : String, *,
                        context : Int32 = 3, algorithm : Algorithm = Myers.new) : String
    EditFormat.render_udiff(old, new, old_path, new_path, context: context, algorithm: algorithm)
  end

  def self.render_replace(old : String, new : String, path : String, *,
                          context : Int32 = 3, algorithm : Algorithm = Myers.new) : String
    EditFormat.render_replace(old, new, path, context: context, algorithm: algorithm)
  end

  def self.merge(base : String, ours : String, theirs : String, *,
                 ours_label   : String    = "ours",
                 theirs_label : String    = "theirs",
                 algorithm    : Algorithm = Myers.new) : Merge::Result
    Merge.merge(base, ours, theirs, ours_label, theirs_label, algorithm)
  end

  def self.stat(edits : Array(Edit)) : Stat
    insertions = 0
    deletions  = 0
    edits.each do |e|
      case e.kind
      when .insert? then insertions += e.b_len
      when .delete? then deletions += e.a_len
      end
    end
    Stat.new(insertions, deletions)
  end

  def self.stat(old_source : String, new_source : String, algorithm : Algorithm = Myers.new) : Stat
    stat(diff_lines(old_source, new_source, algorithm))
  end

  def self.apply(a : Indexable(T), b : Indexable(T), edits : Array(Edit)) : Array(T) forall T
    result = [] of T
    edits.each do |e|
      case e.kind
      when .equal?  then result.concat(a[e.a_pos, e.a_len])
      when .insert? then result.concat(b[e.b_pos, e.b_len])
      end
    end
    result
  end
end
