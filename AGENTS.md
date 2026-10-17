# AGENTS.md

## Layout

- `src/delta.cr` — entry point: requires, `VERSION`, top-level API (`Delta.diff`, `Delta.diff_lines`, `Delta.unified_diff`, `Delta.apply_patch`, `Delta.parse_patch`, `Delta.apply`).
- `src/delta/edit.cr` — `Kind` enum and `Edit` op struct (`a_pos`/`a_len` into old, `b_pos`/`b_len` into new).
- `src/delta/tokenizer.cr` — interns sequence elements / text lines to `Int32` tokens; `Lines` exposes zero-copy `Bytes` line views.
- `src/delta/algorithm.cr` — `Algorithm` contract plus shared `emit` (merge adjacent ops) and `normalize` (delete-before-insert ordering).
- `src/delta/myers.cr` — Myers O(ND), linear-space middle snake; `diff_region` is reused by the other algorithms as their fallback.
- `src/delta/histogram.cr` / `src/delta/patience.cr` — histogram and patience diffs, Myers fallback.
- `src/delta/compaction.cr` — slides change groups to blank-line boundaries (git xdiff-style), on by default.
- `src/delta/stat.cr` — insertion/deletion counts.
- `src/delta/hunk.cr` — groups edits into context-bounded hunks.
- `src/delta/unified.cr` — unified diff rendering (streaming to `IO`).
- `src/delta/patch.cr` — unified diff parsing, all-or-nothing application with drift tolerance, reverse patch, multi-file (`apply_to_dir`) apply; `PatchError`.
- `src/delta/merge.cr` — three-way merge with conflict markers; `MergeResult`.
- `src/delta/words.cr` — whitespace-delimited word tokenizer and inline word-diff markup.
- `spec/` — `crystal spec`; round-trip properties hold for all three algorithms.
- `bench/` — `crystal run --release bench/diff_bench.cr` and `bench/unified_bench.cr`.

## Commands

```console
crystal spec                                    # full suite
crystal spec spec/myers_spec.cr                 # one file
crystal run --release bench/diff_bench.cr       # benchmarks (always --release)
```

## Code standards

- Every file starts with a comment containing its own path (e.g. `# src/delta/myers.cr`); no other comments.
- Compiler-friendly, performance-focused, idiomatic; data-driven design.
- Never use `out` as an identifier (reserved keyword).
- Never touch the `version` field in `shard.yml`.
- Keep `README.md` (public API) and this file in sync with code changes.
- This repo is watched by the zentry daemon: never run `git commit`/`git push` by hand; saving is automatic.

## Invariants

- An edit list always fully covers both sequences; `Delta.apply(a, b, edits) == b` for every algorithm.
- `Delta.apply_patch(a, Delta.unified_diff(a, b)) == b`, byte-exact including a missing trailing newline.
- Op order is canonical: deletes before inserts at the same position; adjacent same-kind ops are merged.
