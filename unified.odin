package diff

import "base:runtime"
import "core:strconv"
import "core:strings"

// DEFAULT_CONTEXT is the number of unchanged lines that unified shows around each change, matching `diff -u`.
DEFAULT_CONTEXT :: 3

// NO_NEWLINE_MARKER follows a line that has no line terminator in unified output.
NO_NEWLINE_MARKER :: "\\ No newline at end of file"

// Unified_Error lists the ways unified output can fail before it allocates.
Unified_Error :: enum {
	None,
	// The number of context lines was negative.
	Negative_Context,
	// An edit script referred to lines outside the inputs it came with.
	Edits_Out_Of_Range,
}

/*
Hunk is one group of nearby changes plus the unchanged lines around them.

Line numbers are zero-based indices into the inputs. The `edits` slice holds
the runs inside the hunk, with the leading and trailing `.Equal` runs trimmed
to the requested context.
*/
Hunk :: struct {
	a_start: int,
	a_count: int,
	b_start: int,
	b_count: int,
	edits:   []Edit,
}

/*
split_lines splits `text` after every `\n`. Each line keeps its terminator,
so joining the lines gives back `text`, and a final line without a newline
stays distinguishable from one with it. A `\r` before the `\n` stays part of
the line.

Inputs:
- text: the text to split.
- allocator: allocates the returned slice.

Returns:
- lines: substrings of `text`, which they borrow, so keep `text` alive while
  using them. Free the slice with `delete(lines, allocator)`. Empty text gives
  an empty slice.
- err: an allocator error.
*/
split_lines :: proc(text: string, allocator := context.allocator) -> (lines: []string, err: Error) {
	count := strings.count(text, "\n")
	if len(text) > 0 && text[len(text) - 1] != '\n' {
		count += 1
	}
	lines = make([]string, count, allocator) or_return
	start, n := 0, 0
	for i in 0 ..< len(text) {
		if text[i] == '\n' {
			lines[n] = text[start:i + 1]
			n += 1
			start = i + 1
		}
	}
	if start < len(text) {
		lines[n] = text[start:]
	}
	return lines, nil
}

/*
hunks groups the changes of `edits` into hunks with `context_lines` unchanged
lines on each side. Two changes separated by at most `2 * context_lines`
unchanged lines share a hunk, as in `diff -u`.

Inputs:
- edits: an edit script from diff, diff_lines or diff_by.
- context_lines: how many unchanged lines to keep around each change.
- allocator: allocates the hunks and their edit slices.

Returns:
- result: the hunks, owned by the caller; free with `hunks_destroy(result, allocator)`.
  It is empty when `edits` has no changes.
- err: `.Negative_Context` when `context_lines < 0`, or an allocator error.
*/
hunks :: proc(
	edits: []Edit,
	context_lines := DEFAULT_CONTEXT,
	allocator := context.allocator,
) -> (
	result: []Hunk,
	err: Error,
) {
	if context_lines < 0 {
		return nil, .Negative_Context
	}
	out := make([dynamic]Hunk, 0, 0, allocator) or_return
	defer if err != nil {
		for h in out {
			delete(h.edits, allocator)
		}
		delete(out)
	}

	i := 0
	for i < len(edits) {
		if edits[i].op == .Equal {
			i += 1
			continue
		}
		h: Hunk
		h, i = collect_hunk(edits, i, context_lines, allocator) or_return
		if _, aerr := append(&out, h); aerr != nil {
			delete(h.edits, allocator)
			return nil, aerr
		}
	}
	shrink(&out) or_return
	return out[:], nil
}

/*
collect_hunk builds the hunk whose first change is `edits[first]` and returns
the index of the first edit after it.
*/
@(private)
collect_hunk :: proc(
	edits: []Edit,
	first, context_lines: int,
	allocator: runtime.Allocator,
) -> (
	h: Hunk,
	next: int,
	err: runtime.Allocator_Error,
) {
	group := make([dynamic]Edit, 0, 4, allocator) or_return
	defer if err != nil {
		delete(group)
	}

	// Leading context: the tail of the run before the first change.
	if first > 0 {
		e := edits[first - 1]
		c := min(context_lines, e.count)
		if c > 0 {
			append(&group, Edit{.Equal, e.a_start + e.count - c, e.b_start + e.count - c, c}) or_return
		}
	}
	next = first
	for next < len(edits) {
		e := edits[next]
		if e.op == .Equal && (next == len(edits) - 1 || e.count > 2 * context_lines) {
			break
		}
		append(&group, e) or_return
		next += 1
	}
	// Trailing context: the head of the run after the last change.
	if next < len(edits) {
		e := edits[next]
		c := min(context_lines, e.count)
		if c > 0 {
			append(&group, Edit{.Equal, e.a_start, e.b_start, c}) or_return
		}
	}

	h.a_start = group[0].a_start
	h.b_start = group[0].b_start
	for e in group {
		switch e.op {
		case .Equal:
			h.a_count += e.count
			h.b_count += e.count
		case .Delete:
			h.a_count += e.count
		case .Insert:
			h.b_count += e.count
		}
	}
	shrink(&group) or_return
	h.edits = group[:]
	return h, next, nil
}

// hunks_destroy frees hunks returned by hunks, including every edit slice.
hunks_destroy :: proc(hs: []Hunk, allocator := context.allocator) {
	for h in hs {
		delete(h.edits, allocator)
	}
	delete(hs, allocator)
}

/*
unified returns the unified diff that turns text `a` into text `b`, in the
format of `diff -u` without timestamps.

Inputs:
- a: the old text.
- b: the new text.
- a_name: the name on the `---` header line.
- b_name: the name on the `+++` header line.
- context_lines: how many unchanged lines to show around each change.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- patch: the unified diff, owned by the caller; free with `delete(patch, allocator)`.
  It is the empty string when the texts are equal.
- err: `.Negative_Context` when `context_lines < 0`, or an allocator error.

Example:
	patch, err := diff.unified("a\nb\n", "a\nc\n", "old.txt", "new.txt")
	defer delete(patch)
	// --- old.txt
	// +++ new.txt
	// @@ -1,2 +1,2 @@
	//  a
	// -b
	// +c
*/
unified :: proc(
	a, b: string,
	a_name := "a",
	b_name := "b",
	context_lines := DEFAULT_CONTEXT,
	allocator := context.allocator,
) -> (
	patch: string,
	err: Error,
) {
	if context_lines < 0 {
		return "", .Negative_Context
	}
	a_lines := split_lines(a, allocator) or_return
	defer delete(a_lines, allocator)
	b_lines := split_lines(b, allocator) or_return
	defer delete(b_lines, allocator)
	edits := diff_lines(a_lines, b_lines, allocator) or_return
	defer delete(edits, allocator)
	return unified_from_edits(a_lines, b_lines, edits, a_name, b_name, context_lines, allocator)
}

/*
unified_from_edits formats an existing line edit script as a unified diff.
Use it when you already hold the lines and the edits, for example to show the
same diff with several context sizes.

Inputs:
- a_lines: the old lines, with terminators, as split_lines returns them.
- b_lines: the new lines.
- edits: the edit script between `a_lines` and `b_lines`.
- a_name: the name on the `---` header line.
- b_name: the name on the `+++` header line.
- context_lines: how many unchanged lines to show around each change.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- patch: the unified diff, owned by the caller; free with `delete(patch, allocator)`.
  It is the empty string when `edits` has no changes.
- err: `.Negative_Context` when `context_lines < 0`, `.Edits_Out_Of_Range`
  when an edit points past the end of a line slice, or an allocator error.
*/
unified_from_edits :: proc(
	a_lines, b_lines: []string,
	edits: []Edit,
	a_name := "a",
	b_name := "b",
	context_lines := DEFAULT_CONTEXT,
	allocator := context.allocator,
) -> (
	patch: string,
	err: Error,
) {
	if context_lines < 0 {
		return "", .Negative_Context
	}
	for e in edits {
		if e.count < 0 || e.a_start < 0 || e.b_start < 0 {
			return "", .Edits_Out_Of_Range
		}
		a_end := e.a_start + (e.op == .Insert ? 0 : e.count)
		b_end := e.b_start + (e.op == .Delete ? 0 : e.count)
		if a_end > len(a_lines) || b_end > len(b_lines) {
			return "", .Edits_Out_Of_Range
		}
	}

	hs := hunks(edits, context_lines, allocator) or_return
	defer hunks_destroy(hs, allocator)
	if len(hs) == 0 {
		return "", nil
	}

	sb := strings.builder_make(allocator) or_return
	defer if err != nil {
		strings.builder_destroy(&sb)
	}
	write_header(&sb, "--- ", a_name) or_return
	write_header(&sb, "+++ ", b_name) or_return
	for h in hs {
		write_string(&sb, "@@ -") or_return
		write_range(&sb, h.a_start, h.a_count) or_return
		write_string(&sb, " +") or_return
		write_range(&sb, h.b_start, h.b_count) or_return
		write_string(&sb, " @@\n") or_return
		for e in h.edits {
			for k in 0 ..< e.count {
				switch e.op {
				case .Equal:
					write_line(&sb, ' ', a_lines[e.a_start + k]) or_return
				case .Delete:
					write_line(&sb, '-', a_lines[e.a_start + k]) or_return
				case .Insert:
					write_line(&sb, '+', b_lines[e.b_start + k]) or_return
				}
			}
		}
	}
	return strings.to_string(sb), nil
}

// write_string appends `s` and reports an allocation failure.
@(private)
write_string :: proc(sb: ^strings.Builder, s: string) -> runtime.Allocator_Error {
	if strings.write_string(sb, s) != len(s) {
		return .Out_Of_Memory
	}
	return nil
}

// write_header appends one `---` or `+++` line.
@(private)
write_header :: proc(sb: ^strings.Builder, prefix, name: string) -> runtime.Allocator_Error {
	write_string(sb, prefix) or_return
	write_string(sb, name) or_return
	return write_string(sb, "\n")
}

// write_range appends a hunk range in `diff -u` form: `start,count`, with the count left out when it is 1.
@(private)
write_range :: proc(sb: ^strings.Builder, start, count: int) -> runtime.Allocator_Error {
	buf: [32]byte
	// An empty range names the line before it, so the zero-based start is already right.
	line := count == 0 ? start : start + 1
	write_string(sb, strconv.write_int(buf[:], i64(line), 10)) or_return
	if count != 1 {
		write_string(sb, ",") or_return
		write_string(sb, strconv.write_int(buf[:], i64(count), 10)) or_return
	}
	return nil
}

// write_line appends one hunk body line, adding the no-newline marker when the line has no terminator.
@(private)
write_line :: proc(sb: ^strings.Builder, prefix: byte, line: string) -> runtime.Allocator_Error {
	if strings.write_byte(sb, prefix) != 1 {
		return .Out_Of_Memory
	}
	write_string(sb, line) or_return
	if len(line) == 0 || line[len(line) - 1] != '\n' {
		write_string(sb, "\n" + NO_NEWLINE_MARKER + "\n") or_return
	}
	return nil
}
