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
```

Render a unified diff:

```crystal
patch = Delta.unified_diff(old_text, new_text,
  context: 3,                  # lines of context around each change
  old_path: "a/file.cr",       # optional; headers omitted when unset
  new_path: "b/file.cr")
```

Parse and apply a unified diff (validates all hunks before writing; raises `Delta::PatchError` on mismatch; tolerates line-number drift):

```crystal
files = Delta.parse_patch(patch_text)   # => Array(Delta::Patch::FilePatch)
result = Delta.apply_patch(old_text, patch_text)
```

Choose an algorithm:

```crystal
Delta.diff_lines(a, b, algorithm: Delta::Myers.new)     # default: minimal edit script
Delta.diff_lines(a, b, algorithm: Delta::Histogram.new) # good on churned/moved code
Delta.diff_lines(a, b, algorithm: Delta::Patience.new)  # anchors on unique lines
```

All three produce valid diffs (applying the edits to the old input always yields the new input); they differ in edit minimality and how readable the result is on moved or heavily repeated content.

Hunks are "compacted" by default: change groups slide across identical lines to sit at blank-line boundaries, matching git's xdiff behavior. Pass `compact: false` to `diff` / `diff_lines` / `unified_diff` to disable it.

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

## Performance

- All comparisons run on `Slice(Int32)` tokens — integer compares, cache-friendly.
- Line tokenization hashes byte ranges directly from the source strings; zero per-line string allocations in the diff hot path.
- Myers runs in linear space (divide-and-conquer middle snake) with shared flat buffers reused across recursion.
- Unified rendering streams to `IO` in a single pass.

Benchmarks (run in release mode):

```console
crystal run --release bench/diff_bench.cr     # algorithm comparison across workloads
crystal run --release bench/unified_bench.cr  # render/parse/apply throughput
```

Snapshot (Crystal 1.21, release mode, ThinkPad X13 i5-1240P):

```text
   myers small (100 lines)  83.5k ips ( 12.0µs)   17.1kB/op   fastest
   histogram small          51.1k ips ( 19.6µs)   21.6kB/op   1.63× slower
    patience small          42.3k ips ( 23.6µs)   27.6kB/op   1.97× slower
   myers 50k lines 5% churn    24.7 ips (40.4ms)   6.31MB/op   fastest
histogram 50k lines 5% churn     3.7 ips (268ms)   7.03MB/op   6.64× slower
 patience 50k lines 5% churn    23.3 ips (42.9ms)  7.07MB/op   1.06× slower
   myers full rewrite (10k)     2.0 ips (490ms)    3.17MB/op   fastest
histogram full rewrite           2.0 ips (505ms)   4.17MB/op   1.03× slower
 patience full rewrite           2.0 ips (494ms)   4.67MB/op   1.01× slower
```

Myers (the default) is the fastest general-purpose choice. Histogram anchors one match per recursion level, so heavily repeated lines (the synthetic 50k workload reuses 5k distinct lines) degrade it — on real code, where lines are mostly unique, it tracks much closer and produces more readable diffs around moved blocks.

Unified diff pipeline on a 50k-line file with 5% churn (249kB patch): render 69ms (diff + tokenize + hunks + emit), parse 3.3ms, apply 4.6ms.

## Development

```console
crystal spec  # run the test suite
```
