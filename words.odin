package diff

import "base:runtime"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

/*
Text_Edit is one run of a text diff. For `.Equal` and `.Delete` runs, `text`
is a substring of the old text; for `.Insert` runs it is a substring of the
new text.
*/
Text_Edit :: struct {
	op:   Op,
	text: string,
}

/*
tokenize_words splits `text` into tokens for diff_words. A token is a run of
letters, digits and underscores, a run of whitespace, or any other single
character. Joining the tokens gives back `text`. Invalid UTF-8 bytes become
single-byte tokens.

Inputs:
- text: the text to split.
- allocator: allocates the returned slice.

Returns:
- tokens: substrings of `text`, which they borrow. Free the slice with
  `delete(tokens, allocator)`.
- err: an allocator error.
*/
tokenize_words :: proc(text: string, allocator := context.allocator) -> (tokens: []string, err: Error) {
	out := make([dynamic]string, 0, len(text) / 4 + 1, allocator) or_return
	defer if err != nil {
		delete(out)
	}
	i := 0
	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		class := rune_class(r)
		j := i + size
		if class != .Other {
			for j < len(text) {
				r2, size2 := utf8.decode_rune_in_string(text[j:])
				if rune_class(r2) != class {
					break
				}
				j += size2
			}
		}
		append(&out, text[i:j]) or_return
		i = j
	}
	shrink(&out) or_return
	return out[:], nil
}

/*
diff_words compares two texts word by word, the way `git diff --word-diff`
does. Whitespace and punctuation count as tokens too, so the result covers
both texts completely: joining the `.Equal` and `.Delete` runs gives `a`, and
joining the `.Equal` and `.Insert` runs gives `b`.

Inputs:
- a: the old text.
- b: the new text.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- edits: the runs, owned by the caller; free with `delete(edits, allocator)`.
  Their strings borrow from `a` and `b`.
- err: an allocator error.

Example:
	edits, err := diff.diff_words("the quick fox", "the slow fox")
	defer delete(edits)
	// {.Equal, "the "}, {.Delete, "quick"}, {.Insert, "slow"}, {.Equal, " fox"}
*/
diff_words :: proc(a, b: string, allocator := context.allocator) -> (edits: []Text_Edit, err: Error) {
	a_tokens := tokenize_words(a, allocator) or_return
	defer delete(a_tokens, allocator)
	b_tokens := tokenize_words(b, allocator) or_return
	defer delete(b_tokens, allocator)
	script := diff_lines(a_tokens, b_tokens, allocator) or_return
	defer delete(script, allocator)

	// Byte offset where each token starts, plus one for the end of the text.
	a_offsets := token_offsets(a_tokens, allocator) or_return
	defer delete(a_offsets, allocator)
	b_offsets := token_offsets(b_tokens, allocator) or_return
	defer delete(b_offsets, allocator)

	out := make([]Text_Edit, len(script), allocator) or_return
	for e, i in script {
		switch e.op {
		case .Equal, .Delete:
			out[i] = {e.op, a[a_offsets[e.a_start]:a_offsets[e.a_start + e.count]]}
		case .Insert:
			out[i] = {e.op, b[b_offsets[e.b_start]:b_offsets[e.b_start + e.count]]}
		}
	}
	return out, nil
}

/*
format_word_diff renders the result of diff_words inline, wrapping deleted
text in `[-` and `-]` and inserted text in `{+` and `+}`, as
`git diff --word-diff=plain` does.

Inputs:
- edits: runs from diff_words.
- allocator: allocates the result.

Returns:
- result: the rendered text, owned by the caller; free with `delete(result, allocator)`.
- err: an allocator error.

Example:
	// "the [-quick-]{+slow+} fox"
*/
format_word_diff :: proc(edits: []Text_Edit, allocator := context.allocator) -> (result: string, err: Error) {
	size := 0
	for e in edits {
		size += len(e.text) + 4
	}
	sb := strings.builder_make_len_cap(0, size, allocator) or_return
	defer if err != nil {
		strings.builder_destroy(&sb)
	}
	for e in edits {
		switch e.op {
		case .Equal:
			write_string(&sb, e.text) or_return
		case .Delete:
			write_string(&sb, "[-") or_return
			write_string(&sb, e.text) or_return
			write_string(&sb, "-]") or_return
		case .Insert:
			write_string(&sb, "{+") or_return
			write_string(&sb, e.text) or_return
			write_string(&sb, "+}") or_return
		}
	}
	return strings.to_string(sb), nil
}

// Rune_Class decides which runes tokenize_words groups together.
@(private)
Rune_Class :: enum u8 {
	Word,
	Space,
	Other,
}

@(private)
rune_class :: proc(r: rune) -> Rune_Class {
	switch {
	case r == utf8.RUNE_ERROR:
		return .Other
	case r == '_' || unicode.is_letter(r) || unicode.is_digit(r):
		return .Word
	case unicode.is_space(r):
		return .Space
	}
	return .Other
}

// token_offsets returns the start offset of every token and the total length at the end.
@(private)
token_offsets :: proc(tokens: []string, allocator: runtime.Allocator) -> (offsets: []int, err: runtime.Allocator_Error) {
	offsets = make([]int, len(tokens) + 1, allocator) or_return
	for t, i in tokens {
		offsets[i + 1] = offsets[i] + len(t)
	}
	return offsets, nil
}
