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

Parse and apply a unified diff (validates all hunks before writing; raises `Delta::PatchError` on mismatch; tolerates line-number drift):

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
crystal run --release bench/memory_bench.cr   # workspace allocation comparison
```

Snapshot (Crystal 1.21, release mode, ThinkPad X13 i5-1240P):

### Diff Algorithms (`bench/diff_bench.cr`)

| Scenario | Algorithm | Iterations/s | Time/op | Variance | Memory/op | Relative |
| --- | --- | --- | --- | --- | --- | --- |
| **Small** | Myers | 91.30k | 10.95µs | ± 4.74% | 17.3kB | fastest |
| **Small** | Histogram | 58.26k | 17.16µs | ± 10.02% | 21.8kB | 1.57× slower |
| **Small** | Patience | 47.40k | 21.10µs | ± 9.44% | 27.8kB | 1.93× slower |
| **50k lines (5% churn)** | Myers | 31.47 | 31.78ms | ± 2.91% | 6.45MB | fastest |
| **50k lines (5% churn)** | Histogram | 29.86 | 33.49ms | ± 3.14% | 6.95MB | 1.05× slower |
| **50k lines (5% churn)** | Patience | 29.17 | 34.28ms | ± 2.54% | 7.20MB | 1.08× slower |
| **Full rewrite** | Patience | 2.54 | 393.26ms | ± 0.95% | 4.67MB | fastest |
| **Full rewrite** | Myers | 2.54 | 394.28ms | ± 0.33% | 3.17MB | 1.00× slower |
| **Full rewrite** | Histogram | 2.52 | 396.73ms | ± 0.47% | 4.17MB | 1.01× slower |

### Unified Patch Operations (`bench/unified_bench.cr`)

*Patch size: 248,619 bytes (50k lines)*

| Operation | Iterations/s | Time/op | Variance | Memory/op | Relative |
| --- | --- | --- | --- | --- | --- |
| **patch parse 50k** | 359.25 | 2.78ms | ± 5.09% | 2.47MB | fastest |
| **patch apply 50k** | 252.51 | 3.96ms | ± 4.46% | 4.38MB | 1.42× slower |
| **unified render 50k** | 18.13 | 55.14ms | ± 3.31% | 8.07MB | 19.81× slower |

### Memory Allocation (`bench/memory_bench.cr`)

#### Diff Engine Allocation (Pre-tokenized, 50k lines)

Algorithm | Without Workspace | With Workspace
--- | --- | ---
**Myers** | 3.47 MB | 0.0 kB
**Histogram** | 3.97 MB | 0.0 kB
**Patience** | 4.22 MB | 0.1 kB

#### Full `diff_lines` Allocation (Includes Tokenization, 50k lines)

Algorithm | Without Workspace | With Workspace
--- | --- | ---
**Myers** | 6.93 MB | 2.74 MB

Myers (the default) and Histogram are effectively tied on typical workloads; Histogram falls back to Myers when the rarest common element is too frequent, so it no longer degrades on heavily repeated content while still producing readable diffs around unique lines. Patience anchors on unique lines and is comparable on all but the most repetitive inputs.

Unified diff pipeline on a 50k-line file with 5% churn (249kB patch): render 92ms (diff + tokenize + compact + hunks + emit), parse 4.4ms, apply 6.0ms.

## Development

```console
crystal spec  # run the test suite
```
