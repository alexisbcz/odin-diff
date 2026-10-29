# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-10-29

### Fixed

- `parse_patch` no longer reserves memory from the hunk header counts alone. A short patch that claimed millions of lines made it reserve gigabytes.
- `parse_patch` returns `Malformed_Hunk_Line` when `+`, `-` or space lines follow a hunk past the line counts in its header. Before, it dropped those lines and the patch applied only in part.
- `apply_patch` checks a `Patch` built by hand: a hunk whose lines disagree with its counts returns `Malformed_Hunk_Line`, and huge starts or counts return an error. Before, both could panic.
- `unified` and `hunks` with `max(int)` lines of context give one hunk. Before, `2 * context` overflowed and gave overlapping hunks that `apply` rejected.
- `unified_from_edits` returns `Edits_Out_Of_Range` for edit counts so large that adding them overflows. Before, it panicked.
- `tokenize_words` and `diff_words` keep grapheme clusters whole. A combining accent no longer splits from its letter, and emoji made of several code points stay one token.

## [0.1.0] - 2026-10-29

### Added

- `diff`, `diff_by` and `diff_lines`: minimal edit scripts with the linear-space Myers O(ND) algorithm.
- `edit_counts` to count the deletions and insertions of a script.
- `split_lines`, `hunks` and `hunks_destroy` for line-based work.
- `unified` and `unified_from_edits`: unified diff output compatible with `diff -u`, with configurable context.
- `parse_patch`, `apply_patch`, `apply` and `patch_destroy`: parse single-file unified diffs and apply them strictly.
- `tokenize_words`, `diff_words` and `format_word_diff` for word-level diffs.
- `Error` union with `Diff_Error`, `Unified_Error`, `Patch_Error` and allocator errors.
- A runnable example under `examples/basic`.

[Unreleased]: https://github.com/alexisbcz/odin-diff/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/alexisbcz/odin-diff/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/alexisbcz/odin-diff/releases/tag/v0.1.0
