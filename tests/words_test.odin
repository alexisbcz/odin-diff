package diff_tests

import diff ".."
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"

@(test)
test_tokenize_words_groups_words_and_spaces :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	tokens, err := diff.tokenize_words("foo_bar  42, x\n")
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	want := []string{"foo_bar", "  ", "42", ",", " ", "x", "\n"}
	if testing.expect_value(t, len(tokens), len(want)) {
		for w, i in want {
			testing.expect_value(t, tokens[i], w)
		}
	}
}

@(test)
test_tokenize_words_splits_each_punctuation_mark :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	tokens, err := diff.tokenize_words("a->b")
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	want := []string{"a", "-", ">", "b"}
	if testing.expect_value(t, len(tokens), len(want)) {
		for w, i in want {
			testing.expect_value(t, tokens[i], w)
		}
	}
}

@(test)
test_tokenize_words_understands_unicode_letters :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	tokens, err := diff.tokenize_words("café über naïve")
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	want := []string{"café", " ", "über", " ", "naïve"}
	if testing.expect_value(t, len(tokens), len(want)) {
		for w, i in want {
			testing.expect_value(t, tokens[i], w)
		}
	}
}

@(test)
test_tokenize_words_keeps_invalid_utf8_bytes :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	text := "ab\xff\xfecd"
	tokens, err := diff.tokenize_words(text)
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	want := []string{"ab", "\xff", "\xfe", "cd"}
	if testing.expect_value(t, len(tokens), len(want)) {
		for w, i in want {
			testing.expect_value(t, tokens[i], w)
		}
	}
	joined := strings.concatenate(tokens)
	defer delete(joined)
	testing.expect_value(t, joined, text)
}

@(test)
test_tokenize_words_empty_text :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	tokens, err := diff.tokenize_words("")
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(tokens), 0)
}

@(test)
test_diff_words_replaces_one_word :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff_words("the quick fox", "the slow fox")
	defer delete(edits)
	testing.expect_value(t, err, nil)
	want := []diff.Text_Edit{{.Equal, "the "}, {.Delete, "quick"}, {.Insert, "slow"}, {.Equal, " fox"}}
	if testing.expect_value(t, len(edits), len(want)) {
		for w, i in want {
			testing.expect_value(t, edits[i], w)
		}
	}
}

@(test)
test_diff_words_runs_rebuild_both_texts :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "Odin is a general-purpose language, built for high performance."
	b := "Odin is a general purpose programming language built for joy and performance!"
	edits, err := diff.diff_words(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)

	old_sb := strings.builder_make()
	defer strings.builder_destroy(&old_sb)
	new_sb := strings.builder_make()
	defer strings.builder_destroy(&new_sb)
	for e in edits {
		if e.op != .Insert {
			strings.write_string(&old_sb, e.text)
		}
		if e.op != .Delete {
			strings.write_string(&new_sb, e.text)
		}
	}
	testing.expect_value(t, strings.to_string(old_sb), a)
	testing.expect_value(t, strings.to_string(new_sb), b)
}

@(test)
test_diff_words_identical_texts_are_one_equal_run :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff_words("same words here", "same words here")
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 1) {
		testing.expect_value(t, edits[0], diff.Text_Edit{.Equal, "same words here"})
	}
}

@(test)
test_diff_words_against_empty_text :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff_words("", "new text")
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 1) {
		testing.expect_value(t, edits[0], diff.Text_Edit{.Insert, "new text"})
	}

	none, none_err := diff.diff_words("", "")
	defer delete(none)
	testing.expect_value(t, none_err, nil)
	testing.expect_value(t, len(none), 0)
}

@(test)
test_format_word_diff_marks_changes_like_git :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff_words("the quick fox", "the slow fox jumps")
	defer delete(edits)
	testing.expect_value(t, err, nil)
	out, format_err := diff.format_word_diff(edits)
	defer delete(out)
	testing.expect_value(t, format_err, nil)
	testing.expect_value(t, out, "the [-quick-]{+slow+} fox{+ jumps+}")
}

@(test)
test_diff_words_survives_allocation_failures :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	for budget in 0 ..< 50 {
		f := Failing_Allocator{context.allocator, budget}
		edits, err := diff.diff_words("one two three", "one 2 three four", failing_allocator(&f))
		if err != nil {
			continue
		}
		testing.expect_value(t, len(edits), 5)
		delete(edits)
		return
	}
	testing.expect(t, false, "diff_words never succeeded")
}

@(test)
test_tokenize_words_keeps_grapheme_clusters_whole :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// A decomposed "é", a family emoji joined with ZWJ, and a flag.
	text := "café \U0001F468‍\U0001F469‍\U0001F467\U0001F1EB\U0001F1F7!"
	tokens, err := diff.tokenize_words(text)
	defer delete(tokens)
	testing.expect_value(t, err, nil)
	want := []string{"café", " ", "\U0001F468‍\U0001F469‍\U0001F467", "\U0001F1EB\U0001F1F7", "!"}
	testing.expectf(t, slice.equal(tokens, want), "got %q", tokens)
}

@(test)
test_diff_words_never_splits_a_combining_mark :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff_words("café noir", "cafe noir")
	defer delete(edits)
	testing.expect_value(t, err, nil)
	inline, format_err := diff.format_word_diff(edits)
	defer delete(inline)
	testing.expect_value(t, format_err, nil)
	testing.expect_value(t, inline, "[-café-]{+cafe+} noir")
}
