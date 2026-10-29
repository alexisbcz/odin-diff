# diff

[![CI](https://github.com/alexisbcz/odin-diff/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-diff/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Minimal diffs for Odin: the Myers O(ND) algorithm in linear space over lines or any slice, unified diff output, strict patch application and a word-level diff.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-diff libs/diff
```

```odin
import "libs/diff"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-diff ~/odin-shared/diff
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:diff"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:diff"

main :: proc() {
	old_text := "milk\neggs\nbread\nbutter\n"
	new_text := "milk\neggs\nsourdough bread\nbutter\njam\n"

	patch, err := diff.unified(old_text, new_text, "list.txt", "list.txt")
	if err != nil {
		fmt.eprintln("unified failed:", err)
		return
	}
	defer delete(patch)
	fmt.print(patch)

	patched, apply_err := diff.apply(old_text, patch)
	if apply_err != nil {
		fmt.eprintln("apply failed:", apply_err)
		return
	}
	defer delete(patched)
	fmt.println("round trip ok:", patched == new_text)
}
```

The program prints:

```text
--- list.txt
+++ list.txt
@@ -1,4 +1,5 @@
 milk
 eggs
-bread
+sourdough bread
 butter
+jam
round trip ok: true
```

## Diffing any slice

`diff` works on any slice whose elements support `==`. The result is an edit script of runs, each with an `op`, a start position in both inputs and a length:

```odin
edits, err := diff.diff([]int{1, 2, 3, 4}, []int{1, 3, 4, 5})
if err != nil {
	return
}
defer delete(edits)
for e in edits {
	fmt.printfln("%v a[%d:] b[%d:] x%d", e.op, e.a_start, e.b_start, e.count)
}
// Equal a[0:] b[0:] x1
// Delete a[1:] b[1:] x1
// Equal a[2:] b[1:] x2
// Insert a[4:] b[3:] x1
```

For types without `==`, or to compare with a looser rule, pass an equality procedure to `diff_by`:

```odin
a := []string{"Hello", "World"}
b := []string{"hello", "world", "again"}
edits, err := diff.diff_by(a, b, proc(x, y: string) -> bool {
	return strings.equal_fold(x, y)
})
defer delete(edits)
```

## Word diffs

`diff_words` compares prose token by token and `format_word_diff` renders the runs inline in the style of `git diff --word-diff`:

```odin
words, err := diff.diff_words("the quick brown fox", "the slow brown fox jumps")
if err != nil {
	return
}
defer delete(words)
inline, format_err := diff.format_word_diff(words)
if format_err != nil {
	return
}
defer delete(inline)
fmt.println(inline) // the [-quick-]{+slow+} brown fox{+ jumps+}
```

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `diff(a, b, allocator)` | Minimal edit script between two slices, comparing with `==` | Yes | `delete` |
| `diff_by(a, b, eq, allocator)` | The same, comparing with `eq` | Yes | `delete` |
| `diff_lines(a, b, allocator)` | Faster `diff` for slices of lines | Yes | `delete` |
| `edit_counts(edits)` | Count deleted and inserted elements | No | Not needed |
| `split_lines(text, allocator)` | Split text into lines that keep their `\n` | Yes | `delete` |
| `hunks(edits, context_lines, allocator)` | Group changes into hunks with context | Yes | `hunks_destroy` |
| `unified(a, b, a_name, b_name, context_lines, allocator)` | Unified diff of two texts | Yes | `delete` |
| `unified_from_edits(a_lines, b_lines, edits, ...)` | Unified diff from an existing script | Yes | `delete` |
| `parse_patch(text, allocator)` | Parse a single-file unified diff | Yes | `patch_destroy` |
| `apply_patch(original, patch, allocator)` | Apply a parsed patch | Yes | `delete` |
| `apply(original, patch, allocator)` | Parse and apply in one step | Yes | `delete` |
| `tokenize_words(text, allocator)` | Split text into words, spaces and symbols | Yes | `delete` |
| `diff_words(a, b, allocator)` | Word-level diff as text runs | Yes | `delete` |
| `format_word_diff(edits, allocator)` | Render a word diff inline | Yes | `delete` |
| `Error` | Union of `Diff_Error`, `Unified_Error`, `Patch_Error` and `runtime.Allocator_Error` | No | Not needed |

Slices from `split_lines` and `tokenize_words`, the runs from `diff_words` and the strings inside a `Patch` borrow from their input text. Keep the text alive while you use them.

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- The core is the linear-space variant of Myers' algorithm. It finds the middle snake of the edit graph with a forward and a reverse search, splits the problem there and solves each half the same way, so memory grows with `N + M` and time with `(N + M) * D`, where `D` is the edit distance. The tests check every result against an O(NM) reference.
- Unified output matches `diff -u`: three lines of context by default, hunk ranges with the count left out when it's one, and `\ No newline at end of file` after a line without a terminator.
- Patching is strict. Every context and deleted line must match at the exact position the hunk header gives, so a patch never applies to the wrong place. There is no fuzz factor and no offset search.
- Every allocating procedure takes `allocator := context.allocator`, frees its scratch memory before returning and says who owns the result. Fallible procedures return `(T, Error)`; the library never panics on bad input.
- The package keeps no global mutable state, so it's safe to use from several threads as long as each value stays on one thread.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
