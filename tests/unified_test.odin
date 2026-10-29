package diff_tests

import diff ".."
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_split_lines_keeps_terminators :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	lines, err := diff.split_lines("a\n\nb\n")
	defer delete(lines)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(lines), 3) {
		testing.expect_value(t, lines[0], "a\n")
		testing.expect_value(t, lines[1], "\n")
		testing.expect_value(t, lines[2], "b\n")
	}
}

@(test)
test_split_lines_empty_text_has_no_lines :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	lines, err := diff.split_lines("")
	defer delete(lines)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(lines), 0)
}

@(test)
test_split_lines_keeps_unterminated_last_line :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	lines, err := diff.split_lines("a\nb")
	defer delete(lines)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(lines), 2) {
		testing.expect_value(t, lines[0], "a\n")
		testing.expect_value(t, lines[1], "b")
	}
}

@(test)
test_split_lines_keeps_carriage_returns :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	lines, err := diff.split_lines("a\r\nb\r\n")
	defer delete(lines)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(lines), 2) {
		testing.expect_value(t, lines[0], "a\r\n")
		testing.expect_value(t, lines[1], "b\r\n")
	}
}

@(test)
test_unified_equal_texts_give_empty_patch :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("same\ntext\n", "same\ntext\n")
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "")
}

@(test)
test_unified_formats_one_change_like_diff_u :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("a\nb\nc\n", "a\nB\nc\n", "old.txt", "new.txt")
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- old.txt\n+++ new.txt\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n")
}

@(test)
test_unified_trims_context_to_three_lines :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "1\n2\n3\n4\n5\n6\n7\n8\n9\n"
	b := "1\n2\n3\n4\nfive\n6\n7\n8\n9\n"
	patch, err := diff.unified(a, b)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+five\n 6\n 7\n 8\n")
}

@(test)
test_unified_zero_context_shows_only_changes :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("a\nb\nc\n", "a\nc\n", context_lines = 0)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -2 +1,0 @@\n-b\n")
}

@(test)
test_unified_rejects_negative_context :: proc(t: ^testing.T) {
	patch, err := diff.unified("a\n", "b\n", context_lines = -1)
	testing.expect_value(t, err, diff.Error(diff.Unified_Error.Negative_Context))
	testing.expect_value(t, patch, "")
}

@(test)
test_unified_merges_changes_with_close_context :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// Six unchanged lines between the changes: exactly 2 * 3, so one hunk.
	a := "x\n1\n2\n3\n4\n5\n6\ny\n"
	b := "X\n1\n2\n3\n4\n5\n6\nY\n"
	patch, err := diff.unified(a, b)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -1,8 +1,8 @@\n-x\n+X\n 1\n 2\n 3\n 4\n 5\n 6\n-y\n+Y\n")
}

@(test)
test_unified_splits_distant_changes_into_hunks :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "x\n1\n2\n3\n4\n5\n6\n7\ny\n"
	b := "X\n1\n2\n3\n4\n5\n6\n7\nY\n"
	patch, err := diff.unified(a, b)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -1,4 +1,4 @@\n-x\n+X\n 1\n 2\n 3\n@@ -6,4 +6,4 @@\n 5\n 6\n 7\n-y\n+Y\n")
}

@(test)
test_unified_from_empty_text :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("", "a\nb\n")
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -0,0 +1,2 @@\n+a\n+b\n")
}

@(test)
test_unified_to_empty_text :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("only\n", "")
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -1 +0,0 @@\n-only\n")
}

@(test)
test_unified_marks_missing_final_newline :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch, err := diff.unified("a\nb", "a\nb\n")
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, patch, "--- a\n+++ b\n@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+b\n")
}

@(test)
test_hunks_report_zero_based_ranges :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits := []diff.Edit{{.Equal, 0, 0, 10}, {.Delete, 10, 10, 1}, {.Insert, 11, 10, 2}, {.Equal, 11, 12, 10}}
	hs, err := diff.hunks(edits, 2)
	defer diff.hunks_destroy(hs)
	testing.expect_value(t, err, nil)
	if !testing.expect_value(t, len(hs), 1) {
		return
	}
	h := hs[0]
	testing.expect_value(t, h.a_start, 8)
	testing.expect_value(t, h.a_count, 5)
	testing.expect_value(t, h.b_start, 8)
	testing.expect_value(t, h.b_count, 6)
	if testing.expect_value(t, len(h.edits), 4) {
		testing.expect_value(t, h.edits[0], diff.Edit{.Equal, 8, 8, 2})
		testing.expect_value(t, h.edits[3], diff.Edit{.Equal, 11, 12, 2})
	}
}

@(test)
test_hunks_of_unchanged_script_is_empty :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	hs, err := diff.hunks([]diff.Edit{{.Equal, 0, 0, 5}})
	defer diff.hunks_destroy(hs)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(hs), 0)
}

@(test)
test_hunks_rejects_negative_context :: proc(t: ^testing.T) {
	hs, err := diff.hunks(nil, -3)
	testing.expect_value(t, err, diff.Error(diff.Unified_Error.Negative_Context))
	testing.expect_value(t, len(hs), 0)
}

@(test)
test_unified_from_edits_rejects_edits_past_the_input :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []string{"a\n"}
	b := []string{"b\n"}
	bad := []diff.Edit{{.Delete, 0, 0, 2}}
	patch, err := diff.unified_from_edits(a, b, bad)
	testing.expect_value(t, err, diff.Error(diff.Unified_Error.Edits_Out_Of_Range))
	testing.expect_value(t, patch, "")

	negative := []diff.Edit{{.Insert, -1, 0, 1}}
	_, err = diff.unified_from_edits(a, b, negative)
	testing.expect_value(t, err, diff.Error(diff.Unified_Error.Edits_Out_Of_Range))
}

@(test)
test_unified_from_edits_reuses_a_script :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a, _ := diff.split_lines("1\n2\n3\n")
	defer delete(a)
	b, _ := diff.split_lines("1\n3\n")
	defer delete(b)
	edits, _ := diff.diff_lines(a, b)
	defer delete(edits)

	wide, err1 := diff.unified_from_edits(a, b, edits, "x", "y", 1)
	defer delete(wide)
	narrow, err2 := diff.unified_from_edits(a, b, edits, "x", "y", 0)
	defer delete(narrow)
	testing.expect_value(t, err1, nil)
	testing.expect_value(t, err2, nil)
	testing.expect_value(t, wide, "--- x\n+++ y\n@@ -1,3 +1,2 @@\n 1\n-2\n 3\n")
	testing.expect_value(t, narrow, "--- x\n+++ y\n@@ -2 +1,0 @@\n-2\n")
}

@(test)
test_unified_with_huge_context_gives_one_hunk :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// max(int) means "show the whole file". Doubling it must not overflow
	// into overlapping hunks that apply refuses.
	a := "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"
	b := "1\nX\n3\n4\n5\n6\n7\n8\nY\n10\n"
	patch, err := diff.unified(a, b, context_lines = max(int))
	defer delete(patch)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, strings.count(patch, "@@ -"), 1)
	testing.expect(t, strings.has_prefix(patch, "--- a\n+++ b\n@@ -1,10 +1,10 @@\n"), patch)
	result, apply_err := diff.apply(a, patch)
	defer delete(result)
	testing.expect_value(t, apply_err, nil)
	testing.expect_value(t, result, b)
}

@(test)
test_unified_from_edits_rejects_overflowing_counts :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	lines := []string{"a\n"}
	bad := [][]diff.Edit {
		{{.Delete, 1, 0, max(int)}},
		{{.Insert, 0, max(int), 1}},
		{{.Equal, max(int) - 1, 0, 2}},
	}
	for edits in bad {
		patch, err := diff.unified_from_edits(lines, lines, edits)
		defer delete(patch)
		testing.expectf(t, err == diff.Unified_Error.Edits_Out_Of_Range, "%v: got %v", edits, err)
	}
}
