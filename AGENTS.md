# AGENTS.md

## Layout

- `src/delta.cr` — entry point: requires, `VERSION`, top-level API (`Delta.diff`, `Delta.diff_lines`, `Delta.unified_diff`, `Delta.apply_patch`, `Delta.parse_patch`, `Delta.apply`).
- `src/delta/edit.cr` — `Edit` op struct with nested `Edit::Kind` enum (`a_pos`/`a_len` into old, `b_pos`/`b_len` into new).
- `src/delta/tokenizer.cr` — interns sequence elements / text lines to `Int32` tokens (`Tokenizer::Interner`, `Tokenizer::Lines` zero-copy `Bytes` line views); whitespace/case normalization for ignore options.
- `src/delta/whitespace.cr` — `Whitespace` enum (`None`/`Amount`/`All`) for ignore options.
- `src/delta/workspace.cr` — reusable scratch buffers (V-arrays, count maps, edit lists) for batch workloads.
- `src/delta/algorithm.cr` — `Algorithm` contract plus shared `emit` (merge adjacent ops) and `normalize` (delete-before-insert ordering).
- `src/delta/compaction.cr` — slides change groups to blank-line boundaries (git xdiff-style), on by default.
- `src/delta/stat.cr` — insertion/deletion counts.
- `src/delta/hunk.cr` — groups edits into context-bounded hunks.
- `src/delta/unified.cr` — unified diff rendering (streaming to `IO`).
- `src/delta/patch.cr` — unified diff parsing, all-or-nothing application with drift tolerance, fuzzy (`fuzz:`) apply, reverse patch, multi-file (`apply_to_dir`) apply; `Patch::Error`.
- `src/delta/merge.cr` — three-way merge with conflict markers; `Merge::Result`.
- `src/delta/words.cr` — whitespace-delimited word tokenizer and inline word-diff markup.

```
.
├─╴.gitignore
├─╴AGENTS.md
├─╴README.md
├─╴shard.yml
├─╴bench/                                 # `crystal run --release bench/delta/diff_bench.cr`, `bench/delta/unified_bench.cr`, and `bench/delta/memory_bench.cr`.
├─╴spec/                                  # `crystal spec`; round-trip properties hold for all three algorithms.
╰─╴src/
   ├─╴delta.cr
   ╰─╴delta/
      ├─╴algorithm.cr                     # `Algorithm` contract plus shared `emit` (merge adjacent ops) and `normalize` (delete-before-insert ordering).
      ├─╴compaction.cr                    # slides change groups to blank-line boundaries (git xdiff-style), on by default.
      ├─╴edit.cr                          # `Edit` op struct with nested `Edit::Kind` enum (`a_pos`/`a_len` into old, `b_pos`/`b_len` into new).
      ├─╴edit_format.cr                   # parses/applies/renders aider-style edit formats (whole, SEARCH/REPLACE diff, fenced udiff); opt-in fuzzy search/replace; `EditFormat::Error`.
      ├─╴hunk.cr                          # groups edits into context-bounded hunks.
      ├─╴merge.cr                         # three-way merge with conflict markers; `Merge::Result`.
      ├─╴patch.cr                         # unified diff parsing, all-or-nothing application with drift tolerance, fuzzy (`fuzz:`) apply, reverse patch, multi-file (`apply_to_dir`) apply; `Patch::Error`.
      ├─╴stat.cr                          # insertion/deletion counts.
      ├─╴tokenizer.cr                     # interns sequence elements / text lines to `Int32` tokens (`Tokenizer::Interner`, `Tokenizer::Lines` zero-copy `Bytes` line views); whitespace/case normalization for ignore options.
      ├─╴unified.cr                       # unified diff rendering (streaming to `IO`).
      ├─╴whitespace.cr                    # `Whitespace` enum (`None`/`Amount`/`All`) for ignore options.
      ├─╴words.cr                         # whitespace-delimited word tokenizer and inline word-diff markup.
      ├─╴workspace.cr                     # reusable scratch buffers (V-arrays, count maps, edit lists) for batch workloads.
      ╰─╴algorithms/
         ├─╴myers.cr                      # Myers O(ND), linear-space middle snake; `diff_region` is reused by the other algorithms as their fallback.
         ╰─╴histogram.cr / patience.cr    # histogram and patience diffs; histogram falls back to Myers when the rarest common element is too frequent (`MAX_COUNT`).
```

## Commands

```console
crystal spec                                          # full suite
crystal spec spec/delta/myers_spec.cr                 # one file
crystal run --release bench/delta/diff_bench.cr       # benchmarks (always --release)
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
