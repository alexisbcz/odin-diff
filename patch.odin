package diff

import "base:runtime"
import "core:strconv"
import "core:strings"

// Patch_Error lists the ways parsing or applying a unified diff can fail.
Patch_Error :: enum {
	None,
	// A line starting with `@@` is not a valid `@@ -a,b +c,d @@` header.
	Malformed_Hunk_Header,
	/*
	A hunk body line starts with a character other than ' ', '-', '+' or '\',
	or the hunk has more or fewer lines than its header promises.
	*/
	Malformed_Hunk_Line,
	// The patch ended before a hunk had as many lines as its header promised.
	Truncated_Hunk,
	// The patch has a second `---` header, so it changes more than one file.
	Multiple_Files,
	// A hunk starts before the end of the hunk before it.
	Hunk_Out_Of_Order,
	// A hunk refers to lines past the end of the original text.
	Hunk_Out_Of_Range,
	// A context or deleted line in the patch does not match the original text.
	Context_Mismatch,
}

/*
Patch is a parsed single-file unified diff.

The strings inside a Patch borrow from the text passed to parse_patch, so keep
that text alive while you use the Patch. Release the Patch with patch_destroy.
*/
Patch :: struct {
	// The name after `---`, without a trailing tab and timestamp. Empty when the patch has no header.
	a_name:    string,
	// The name after `+++`, without a trailing tab and timestamp.
	b_name:    string,
	hunks:     []Patch_Hunk,
	allocator: runtime.Allocator,
}

/*
Patch_Hunk is one `@@` section of a Patch. `a_start` and `b_start` are
zero-based line indices: the line numbers from the header minus one, or the
number itself when the count is zero.
*/
Patch_Hunk :: struct {
	a_start: int,
	a_count: int,
	b_start: int,
	b_count: int,
	lines:   []Patch_Line,
}

/*
Patch_Line is one body line of a hunk. `text` is the line without its
one-character prefix, including the `\n` terminator unless the patch marked
the line with `\ No newline at end of file`.
*/
Patch_Line :: struct {
	op:   Op,
	text: string,
}

/*
parse_patch parses a unified diff that changes one file, such as the output of
unified, `diff -u` or `git diff` for a single file. Lines before the first
`---` or `@@` line, such as `diff --git` headers, are ignored, as are lines
between hunks that do not start with `@@` or `---`.

Inputs:
- text: the patch text. The returned Patch borrows from it.
- allocator: allocates the hunk and line slices.

Returns:
- patch: the parsed patch; free with `patch_destroy(&patch)`. Empty input
  gives a patch with no hunks, which applies as a no-op.
- err: a `Patch_Error` describing the first problem, or an allocator error.
  On error nothing needs freeing.
*/
parse_patch :: proc(text: string, allocator := context.allocator) -> (patch: Patch, err: Error) {
	patch.allocator = allocator
	hs := make([dynamic]Patch_Hunk, 0, 0, allocator) or_return
	defer if err != nil {
		for h in hs {
			delete(h.lines, allocator)
		}
		delete(hs)
		patch = {}
	}

	rest := text
	seen_header := false
	for len(rest) > 0 {
		line := next_line(&rest)
		switch {
		case strings.has_prefix(line, "--- "):
			if seen_header || len(hs) > 0 {
				return patch, .Multiple_Files
			}
			patch.a_name = header_name(line[4:])
			if strings.has_prefix(rest, "+++ ") {
				patch.b_name = header_name(next_line(&rest)[4:])
			}
			seen_header = true
		case strings.has_prefix(line, "@@"):
			h := parse_hunk(line, &rest, allocator) or_return
			if _, aerr := append(&hs, h); aerr != nil {
				delete(h.lines, allocator)
				return patch, aerr
			}
		}
	}
	shrink(&hs) or_return
	patch.hunks = hs[:]
	return patch, nil
}

// patch_destroy frees the hunks of `p` and zeroes it. The text it borrowed from is untouched.
patch_destroy :: proc(p: ^Patch) {
	for h in p.hunks {
		delete(h.lines, p.allocator)
	}
	delete(p.hunks, p.allocator)
	p^ = {}
}

/*
apply_patch applies a parsed patch to `original`. It is strict: every context
and deleted line must match the original exactly, at exactly the position the
hunk header gives. It does not search nearby lines or ignore whitespace.

Inputs:
- original: the text the patch was made against.
- p: the parsed patch.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- result: the patched text, owned by the caller; free with `delete(result, allocator)`.
- err: `.Hunk_Out_Of_Order`, `.Hunk_Out_Of_Range`, `.Context_Mismatch`,
  `.Malformed_Hunk_Line` when a hunk's lines disagree with its counts, or an
  allocator error. On error nothing needs freeing. Bad input, including a
  Patch built by hand, never panics.
*/
apply_patch :: proc(original: string, p: Patch, allocator := context.allocator) -> (result: string, err: Error) {
	lines := split_lines(original, allocator) or_return
	defer delete(lines, allocator)

	sb := strings.builder_make_len_cap(0, len(original), allocator) or_return
	defer if err != nil {
		strings.builder_destroy(&sb)
	}

	pos := 0
	for h in p.hunks {
		if h.a_start < pos {
			return "", .Hunk_Out_Of_Order
		}
		// A Patch can be built by hand, so check that the lines agree with
		// the counts before trusting either. Comparing against the room left
		// keeps huge values from overflowing.
		a_lines, b_lines := 0, 0
		for pl in h.lines {
			if pl.op != .Insert {
				a_lines += 1
			}
			if pl.op != .Delete {
				b_lines += 1
			}
		}
		if a_lines != h.a_count || b_lines != h.b_count {
			return "", .Malformed_Hunk_Line
		}
		if h.a_start > len(lines) || h.a_count > len(lines) - h.a_start {
			return "", .Hunk_Out_Of_Range
		}
		for line in lines[pos:h.a_start] {
			write_string(&sb, line) or_return
		}
		k := h.a_start
		for pl in h.lines {
			switch pl.op {
			case .Equal:
				if lines[k] != pl.text {
					return "", .Context_Mismatch
				}
				write_string(&sb, pl.text) or_return
				k += 1
			case .Delete:
				if lines[k] != pl.text {
					return "", .Context_Mismatch
				}
				k += 1
			case .Insert:
				write_string(&sb, pl.text) or_return
			}
		}
		pos = k
	}
	for line in lines[pos:] {
		write_string(&sb, line) or_return
	}
	return strings.to_string(sb), nil
}

/*
apply parses `patch` and applies it to `original` in one step. See parse_patch
and apply_patch for the rules.

Inputs:
- original: the text the patch was made against.
- patch: a single-file unified diff, for example from unified.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- result: the patched text, owned by the caller; free with `delete(result, allocator)`.
- err: a `Patch_Error` or an allocator error. On error nothing needs freeing.

Example:
	patched, err := diff.apply("a\nb\n", "@@ -2 +2 @@\n-b\n+c\n")
	defer delete(patched)
	// patched == "a\nc\n"
*/
apply :: proc(original, patch: string, allocator := context.allocator) -> (result: string, err: Error) {
	p := parse_patch(patch, allocator) or_return
	defer patch_destroy(&p)
	return apply_patch(original, p, allocator)
}

// next_line removes and returns the first line of `rest`, including its `\n` if any.
@(private)
next_line :: proc(rest: ^string) -> string {
	i := strings.index_byte(rest^, '\n')
	line: string
	if i < 0 {
		line, rest^ = rest^, ""
	} else {
		line, rest^ = rest[:i + 1], rest[i + 1:]
	}
	return line
}

// strip_eol removes one trailing `\n` or `\r\n`.
@(private)
strip_eol :: proc(s: string) -> string {
	return strings.trim_suffix(strings.trim_suffix(s, "\n"), "\r")
}

// header_name returns the file name of a `---` or `+++` line, dropping a tab-separated timestamp.
@(private)
header_name :: proc(s: string) -> string {
	name := strip_eol(s)
	if i := strings.index_byte(name, '\t'); i >= 0 {
		name = name[:i]
	}
	return name
}

// parse_hunk parses the header `header` and then consumes the hunk body from `rest`.
@(private)
parse_hunk :: proc(header: string, rest: ^string, allocator: runtime.Allocator) -> (h: Patch_Hunk, err: Error) {
	a_line, a_count, b_line, b_count, ok := parse_hunk_header(strip_eol(header))
	if !ok {
		return {}, .Malformed_Hunk_Header
	}
	h.a_count, h.b_count = a_count, b_count
	h.a_start = a_count == 0 ? a_line : a_line - 1
	h.b_start = b_count == 0 ? b_line : b_line - 1

	// Every body line takes at least one byte, so the rest of the text caps
	// the reservation. Trusting the header would let a tiny patch claiming
	// huge counts reserve gigabytes.
	out := make([dynamic]Patch_Line, 0, min(a_count + b_count, len(rest^)), allocator) or_return
	defer if err != nil {
		delete(out)
	}

	a_left, b_left := a_count, b_count
	for a_left > 0 || b_left > 0 {
		if len(rest) == 0 {
			return {}, .Truncated_Hunk
		}
		line := next_line(rest)
		pl: Patch_Line
		switch line[0] {
		case ' ':
			pl = {.Equal, line[1:]}
		case '\n', '\r':
			// Some editors strip the single space of an empty context line.
			pl = {.Equal, line}
		case '-':
			pl = {.Delete, line[1:]}
		case '+':
			pl = {.Insert, line[1:]}
		case '\\':
			mark_no_newline(out[:])
			continue
		case:
			return {}, .Malformed_Hunk_Line
		}
		if pl.op != .Insert {
			if a_left == 0 {
				return {}, .Malformed_Hunk_Line
			}
			a_left -= 1
		}
		if pl.op != .Delete {
			if b_left == 0 {
				return {}, .Malformed_Hunk_Line
			}
			b_left -= 1
		}
		append(&out, pl) or_return
	}
	// A marker may follow the last body line.
	if strings.has_prefix(rest^, "\\") {
		next_line(rest)
		mark_no_newline(out[:])
	}
	// A body line right after the hunk means the header undercounts it.
	// Ignoring it would silently drop part of the change. A `---` line
	// starts the next file and the `-- ` line is a mail signature, as
	// written by `git format-patch`.
	peek := rest^
	if next := strip_eol(next_line(&peek)); len(next) > 0 {
		switch next[0] {
		case ' ', '+', '-':
			if next != "-- " && !strings.has_prefix(next, "--- ") {
				return {}, .Malformed_Hunk_Line
			}
		}
	}
	shrink(&out) or_return
	h.lines = out[:]
	return h, nil
}

// mark_no_newline drops the line terminator of the last line in `lines`.
@(private)
mark_no_newline :: proc(lines: []Patch_Line) {
	if len(lines) == 0 {
		return
	}
	last := &lines[len(lines) - 1]
	last.text = strings.trim_suffix(last.text, "\n")
}

// parse_hunk_header parses `@@ -a[,b] +c[,d] @@` followed by optional text.
@(private)
parse_hunk_header :: proc(line: string) -> (a_line, a_count, b_line, b_count: int, ok: bool) {
	s := strings.trim_prefix(line, "@@ -")
	if len(s) == len(line) {
		return
	}
	a_line, a_count, s = parse_range(s) or_return
	s = strings.trim_prefix(s, " +") if strings.has_prefix(s, " +") else ""
	if len(s) == 0 {
		return
	}
	b_line, b_count, s = parse_range(s) or_return
	if !strings.has_prefix(s, " @@") {
		return
	}
	// An empty range names the line before it, so line 0 is only valid with count 0.
	if (a_count > 0 && a_line == 0) || (b_count > 0 && b_line == 0) {
		return
	}
	return a_line, a_count, b_line, b_count, true
}

// parse_range parses `start[,count]` and returns the text after it.
@(private)
parse_range :: proc(s: string) -> (start, count: int, rest: string, ok: bool) {
	start, rest = parse_uint(s) or_return
	count = 1
	if strings.has_prefix(rest, ",") {
		count, rest = parse_uint(rest[1:]) or_return
	}
	return start, count, rest, true
}

// parse_uint parses a run of decimal digits at the start of `s`.
@(private)
parse_uint :: proc(s: string) -> (value: int, rest: string, ok: bool) {
	n := 0
	for n < len(s) && s[n] >= '0' && s[n] <= '9' {
		n += 1
	}
	if n == 0 || n > 18 {
		return
	}
	value = strconv.parse_int(s[:n], 10) or_return
	return value, s[n:], true
}
