# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/alexisbcz/odin-diff/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-diff/releases/tag/v0.1.0
