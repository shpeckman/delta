# delta

A fast diff/patch shard for Crystal. Compares sequences with pluggable algorithms — Myers O(ND) (minimal edits, the default), Histogram, and Patience — and produces either a structured edit list or a git-compatible unified diff that can be parsed and applied back.

## Installation

```yaml
dependencies:
  delta:
    github: shpeckman/delta
```

```crystal
require "delta"
```

## Usage

Diff any two sequences (arrays, strings-as-arrays, anything `Indexable`):

```crystal
edits = Delta.diff([1, 2, 3], [1, 4, 3])
edits # => [Edit(Equal a[0,1] b[0,1]), Edit(Delete a[1,1] b[1,0]), Edit(Insert a[2,0] b[1,1]), Edit(Equal a[2,1] b[2,1])]
```

An `Edit` is a compact run: `kind` (`Equal`/`Delete`/`Insert`), `a_pos`/`a_len` into the old sequence, `b_pos`/`b_len` into the new one. `Delete` covers `a[a_pos, a_len]`; `Insert` covers `b[b_pos, b_len]`; `Equal` covers both. Materialize the result with:

```crystal
Delta.apply([1, 2, 3], [1, 4, 3], edits) # => [1, 4, 3]
```

Diff text line by line (fast path: lines are interned as byte slices, no per-line allocations):

```crystal
edits = Delta.diff_lines(old_text, new_text)

Delta.diff_lines(old_text, new_text,
  whitespace: Delta::Whitespace::All,  # None | Amount | All
  ignore_case: true)
```

`Whitespace::All` ignores all whitespace; `Whitespace::Amount` ignores the amount of whitespace but not its presence; `ignore_case` folds case. These affect matching only — reported positions and rendered output always use the original text. Pass the same options to `unified_diff`.

Render a unified diff:

```crystal
patch = Delta.unified_diff(old_text, new_text,
  context: 3,                  # lines of context around each change
  old_path: "a/file.cr",       # optional; headers omitted when unset
  new_path: "b/file.cr")
```

Parse and apply a unified diff (validates all hunks before writing; raises `Delta::Patch::Error` on mismatch; tolerates line-number drift):

```crystal
files = Delta.parse_patch(patch_text)   # => Array(Delta::Patch::FilePatch)
result = Delta.apply_patch(old_text, patch_text)
```

Fuzzy apply tolerates a fixed number of mismatched *context* lines (changed lines must still match exactly), like `patch --fuzz=N`:

```crystal
Delta.apply_patch(almost_matching_text, patch, fuzz: 2)
```

Choose an algorithm:

```crystal
Delta.diff_lines(a, b, algorithm: Delta::Myers.new)     # default: minimal edit script
Delta.diff_lines(a, b, algorithm: Delta::Histogram.new) # good on churned/moved code
Delta.diff_lines(a, b, algorithm: Delta::Patience.new)  # anchors on unique lines
```

All three produce valid diffs (applying the edits to the old input always yields the new input); they differ in edit minimality and how readable the result is on moved or heavily repeated content.

Hunks are "compacted" by default: change groups slide across identical lines to sit at blank-line boundaries, matching git's xdiff behavior. Pass `compact: false` to `diff` / `diff_lines` / `unified_diff` to disable it.

## Reusable workspace

For batch workloads, pass a `Delta::Workspace` to avoid re-allocating scratch buffers (the Myers V-arrays, histogram/patience count maps, edit lists) across calls:

```crystal
ws = Delta::Workspace.new
edits = Delta.diff_lines(a, b, workspace: ws)
more   = Delta.diff_lines(c, d, workspace: ws)   # reuses ws's buffers
```

`Workspace` is not thread-safe by itself; use one per fiber when diffing concurrently. The returned edit array is reused on the next call through the same workspace, so copy it if you need to retain it.

## Three-way merge

```crystal
result = Delta.merge(base, ours, theirs,
  ours_label: "mine", theirs_label: "yours")
result.clean?      # => false when there were conflicts
result.conflicts   # => number of conflict blocks
result.text        # merged content, with <<<<<<< / ======= / >>>>>>> markers
```

Clean regions merge automatically; identical changes taken from both sides merge once; overlapping or abutting changes produce a conflict block.

## Reverse and multi-file patches

```crystal
reversed = Delta.reverse_patch(patch)                 # swap old/new and -/+
Delta.apply_patch(b_text, patch, reverse: true)       # apply the patch backwards

Delta.apply_patch_to_dir(patch, "/path/to/repo", strip: 1)  # like `git apply -p1`
```

`apply_patch_to_dir` handles `/dev/null` file creation and deletion, is all-or-nothing across every file, and rejects absolute paths and `..` traversal.

## Aider-style edit formats

Parse and apply the edit formats used by [aider](https://aider.chat/docs/more/edit-formats.html) — whole-file, SEARCH/REPLACE "diff", and fenced unified diff:

```crystal
edits = Delta.parse_edits(text)                    # => Array(Delta::EditFormat::FileEdit)
new   = Delta.apply_edit(old_text, edits[0])       # apply one edit to in-memory content

Delta.apply_edits(text, "/path/to/repo")           # apply all edits to files (all-or-nothing)
```

`parse_edits` auto-detects the format:

- **whole** — a filename line followed by a fenced block holding the entire new file.
- **diff / diff-fenced** — `<<<<<<< SEARCH / ======= / >>>>>>> REPLACE` blocks; an empty `SEARCH` appends or creates the file; matching tolerates leading-whitespace drift and `...` elision.
- **udiff** — a ` ```diff `-fenced unified diff; hunks apply by search/replace, so `@@` line numbers are ignored.

Pass `valid_files:` to `parse_edits` to resolve basename-only filenames against a known path list. `apply_edits` creates files with parent directories, is all-or-nothing, and rejects absolute paths and `..` traversal. Malformed or non-matching edits raise `Delta::EditFormat::Error`. `editor-diff` and `editor-whole` are prompt-only variants and parse as `diff` and `whole`.

Enable a last-resort similarity match (opt-in, off by default) for noisy LLM output where a `SEARCH` block doesn't match exactly:

```crystal
Delta.apply_edit(text, edit, fuzzy: true)          # accept best match at >= 0.8 similarity
Delta.apply_edit(text, edit, fuzzy: true, threshold: 0.9)
```

Render edits back out — the inverse of `parse_edits` — for feeding an LLM or round-tripping:

```crystal
Delta.render_whole("path/file.py", new_content)
Delta.render_udiff(old, new, "a/f.py", "b/f.py")   # ```diff -fenced unified diff
Delta.render_replace(old, new, "path/file.py")     # SEARCH/REPLACE blocks
```

`render_replace` emits one block per change group with surrounding context so every block locates its change; `render_udiff` reuses `unified_diff`. All three normalize a missing trailing newline (aider behaves the same), and `render_udiff`/`render_replace` return `""` when there is nothing to change.

## JSON documents

`Delta::JSON` diffs and patches `JSON::Any` trees with path-addressed ops, tracks a mutable document through revisions, and streams coalesced changes to watchers.

```crystal
ops = Delta.diff_json(base, value)        # => Array(Delta::JSON::Op)
Delta.apply_json(base, ops) == value      # => true; base is not mutated, unchanged subtrees are shared
```

Ops serialize to compact JSON tuples (`ops.to_json`, `Delta::JSON.parse_ops`):

Op        | Tuple                               | Meaning
----------|-------------------------------------|--------------------------------------------------------
`Replace` | `["r", value]`                      | replace the whole document
`Set`     | `["s", path, value]`                | set a key or index (an index equal to the size appends)
`Delete`  | `["d", path]`                       | remove a key or element
`Append`  | `["a", path, text]`                 | append to a string
`Trim`    | `["t", path, count]`                | drop `count` characters from the start of a string
`Splice`  | `["p", path, index, remove, items]` | array splice
`Move`    | `["m", path, permutation]`          | reorder an array (`new[i] = old[permutation[i]]`)

A path is an array of string keys and integer indices. `Delta::JSON.apply_immutable` copies on write; `Delta::JSON.apply` mutates its input in place (for replicas you own). Invalid paths raise `Errors::InvalidPath`, malformed ops `Errors::InvalidOp`.

Track edits through a draft; consecutive writes to the same leaf and repeated appends fold into one op:

```crystal
tracker  = Delta::JSON::Tracker.new(JSON.parse(%({"items":[],"log":""})))
prepared = tracker.change do |draft|
  draft["items"].push(1, 2, 3)
  draft.append("log", "started")
  draft["items"].sort_by { |item| -item.as_i }
end
prepared.ops       # ops that turn prepared.base into prepared.value
tracker.revision   # => 1
```

`Draft` supports `[]=`, `set`, `delete`, `delete_at`, `append`, `trim`, `push`, `unshift`, `insert`, `concat`, `pop`, `shift`, `splice`, `move`, `reverse`, `sort_by`, `replace`, and `apply(ops)` (rebased onto the draft's path). For optimistic concurrency, `begin_change` / `prepare` / `adopt` split the steps; adopting a preparation from an older revision raises `Errors::Stale`.

Publish to watchers with `State`. Each watcher buffers ops in a `PendingOps` that coalesces leaf writes and collapses to a single `Replace` past its limit (default 10,000 ops), so slow consumers never fall behind unboundedly:

```crystal
state = Delta::JSON::State.new(JSON.parse(%({"log":""})))
watch = state.watch
spawn { watch.each { |frame| send(frame.seq, frame.ops) } }   # blocks until changes arrive or the state closes
state.change { |draft| draft.append("log", "hi") }
state.close                                                    # or `retire` (sends a null Replace first), or `close(error)`
```

`Wire::Encoder` / `Wire::Decoder` are a stateful transport encoding that interns repeated paths as integer ids; a `Replace` resets both sides.

## MessagePack documents

`Delta::Msgpack` provides the same path-addressed op model over `MessagePack::Type` trees (maps with any `MessagePack::Type` keys, including non-string keys):

```crystal
ops = Delta.diff_msgpack(base, value)      # => Array(Delta::Msgpack::Op)
Delta.apply_msgpack(base, ops) == value    # => true; base is not mutated
```

Op codes and paths match the JSON ops above. `Delta::Msgpack.apply_immutable` copies on write and shares unchanged subtrees; `Delta::Msgpack.apply` mutates its input in place. Ops serialize to MessagePack bytes with `Delta::Msgpack.pack_ops` and parse back with `Delta::Msgpack.unpack_ops` (or `unpack_ops(any)`). The JSON-only collaboration layer (`Tracker`/`Draft`/`State`/`Wire`) is not part of the MessagePack surface; `Delta::Msgpack` exposes `diff`, `apply_immutable`, `apply`, `copy`, `pack_ops`, `unpack_ops`, and the `Ops`/`Op` types.

## Diff stats

```crystal
Delta.stat(edits)              # => Delta::Stat (insertions, deletions, total)
Delta.stat(old_text, new_text) # convenience overload
```

## Word and character diffs

```crystal
Delta.diff_words(old, new)  # ops over whitespace-delimited word tokens
Delta.diff_chars(old, new)  # ops over characters
Delta.word_diff(old, new)   # "hello [-world-]{+there+}" inline markup
```

Word tokens are maximal whitespace/non-whitespace runs, so `Delta::Words.tokens(s).join == s` — reconstruct any word diff with `Delta.apply(Delta::Words.tokens(old), Delta::Words.tokens(new), edits).join`.

## Development

```console
crystal spec  # run the test suite
```
