package diff_tests

import diff ".."
import "base:runtime"
import "core:mem"
import "core:testing"

@(test)
test_apply_reverses_unified_on_a_simple_change :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "one\ntwo\nthree\n"
	b := "one\n2\nthree\nfour\n"
	patch, err := diff.unified(a, b)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	result, apply_err := diff.apply(a, patch)
	defer delete(result)
	testing.expect_value(t, apply_err, nil)
	testing.expect_value(t, result, b)
}

@(test)
test_apply_round_trips_random_texts :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	rng := Rng{0xdecafbad}
	for round in 0 ..< 300 {
		a := random_text(&rng, rng_int(&rng, 25))
		defer delete(a)
		b := random_text(&rng, rng_int(&rng, 25))
		defer delete(b)
		patch, err := diff.unified(a, b, context_lines = round % 4)
		defer delete(patch)
		if !testing.expect_value(t, err, nil) {
			return
		}
		result, apply_err := diff.apply(a, patch)
		defer delete(result)
		if !testing.expectf(t, apply_err == nil && result == b, "round %d: %v\n%q\n%q\n%s", round, apply_err, a, b, patch) {
			return
		}
	}
}

@(test)
test_apply_empty_patch_returns_a_copy :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	result, err := diff.apply("keep\nme\n", "")
	defer delete(result)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, result, "keep\nme\n")
}

@(test)
test_apply_accepts_git_headers :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch := "diff --git a/f.txt b/f.txt\n" + "index 3b18e51..e69de29 100644\n" + "--- a/f.txt\n" + "+++ b/f.txt\n" + "@@ -1,2 +1,2 @@ fn main\n" + " hello\n" + "-world\n" + "+odin\n"
	result, err := diff.apply("hello\nworld\n", patch)
	defer delete(result)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, result, "hello\nodin\n")
}

@(test)
test_parse_patch_reads_names_without_timestamps :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	text := "--- old.txt\t2026-10-29 10:00:00\n+++ new.txt\t2026-10-29 11:00:00\n@@ -1 +1 @@\n-a\n+b\n"
	p, err := diff.parse_patch(text)
	defer diff.patch_destroy(&p)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, p.a_name, "old.txt")
	testing.expect_value(t, p.b_name, "new.txt")
}

@(test)
test_parse_patch_fills_hunk_fields :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	text := "@@ -3,2 +3,3 @@\n c\n-d\n+D\n+E\n@@ -0,0 +1 @@\n+z\n"
	p, err := diff.parse_patch(text)
	defer diff.patch_destroy(&p)
	testing.expect_value(t, err, nil)
	if !testing.expect_value(t, len(p.hunks), 2) {
		return
	}
	h := p.hunks[0]
	testing.expect_value(t, h.a_start, 2)
	testing.expect_value(t, h.a_count, 2)
	testing.expect_value(t, h.b_start, 2)
	testing.expect_value(t, h.b_count, 3)
	if testing.expect_value(t, len(h.lines), 4) {
		testing.expect_value(t, h.lines[0], diff.Patch_Line{.Equal, "c\n"})
		testing.expect_value(t, h.lines[1], diff.Patch_Line{.Delete, "d\n"})
		testing.expect_value(t, h.lines[3], diff.Patch_Line{.Insert, "E\n"})
	}
	testing.expect_value(t, p.hunks[1].a_start, 0)
	testing.expect_value(t, p.hunks[1].a_count, 0)
	testing.expect_value(t, p.hunks[1].b_count, 1)
}

@(test)
test_apply_handles_missing_newlines_both_ways :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	pairs := [][2]string{{"a\nb", "a\nb\n"}, {"a\nb\n", "a\nb"}, {"x", "y"}, {"", "z"}, {"z", ""}}
	for pair in pairs {
		patch, err := diff.unified(pair[0], pair[1])
		defer delete(patch)
		testing.expect_value(t, err, nil)
		result, apply_err := diff.apply(pair[0], patch)
		defer delete(result)
		testing.expect_value(t, apply_err, nil)
		testing.expect_value(t, result, pair[1])
	}
}

@(test)
test_apply_reports_context_mismatch :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	result, err := diff.apply("a\nb\n", "@@ -1,2 +1,2 @@\n a\n-x\n+y\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Context_Mismatch))
	testing.expect_value(t, result, "")

	_, err = diff.apply("a\nb\n", "@@ -1,2 +1,2 @@\n q\n-b\n+y\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Context_Mismatch))
}

@(test)
test_apply_reports_hunk_past_the_end :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	_, err := diff.apply("a\n", "@@ -5,1 +5,1 @@\n-e\n+f\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Hunk_Out_Of_Range))
}

@(test)
test_apply_reports_overlapping_hunks :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	patch := "@@ -2,2 +2,2 @@\n b\n-c\n+C\n@@ -1 +1 @@\n-a\n+A\n"
	_, err := diff.apply("a\nb\nc\n", patch)
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Hunk_Out_Of_Order))
}

@(test)
test_parse_patch_rejects_malformed_headers :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	headers := []string{
		"@@\n",
		"@@ -1 @@\n",
		"@@ -a,1 +1 @@\n",
		"@@ -1,2 +1,x @@\n",
		"@@ -1 +1\n",
		"@@ 1 +1 @@\n",
		"@@ -0,1 +1 @@\n",
		"@@ -1 +0 @@\n",
		"@@ -99999999999999999999 +1 @@\n",
	}
	for h in headers {
		p, err := diff.parse_patch(h)
		testing.expectf(t, err == diff.Error(diff.Patch_Error.Malformed_Hunk_Header), "%q gave %v", h, err)
		testing.expect_value(t, len(p.hunks), 0)
	}
}

@(test)
test_parse_patch_rejects_unknown_body_lines :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	_, err := diff.parse_patch("@@ -1,2 +1,2 @@\n a\n?b\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Malformed_Hunk_Line))
}

@(test)
test_parse_patch_rejects_lines_beyond_the_header_counts :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// The header promises one old line, but the body deletes two.
	_, err := diff.parse_patch("@@ -1 +1,2 @@\n-a\n-b\n+c\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Malformed_Hunk_Line))
}

@(test)
test_parse_patch_rejects_truncated_hunk :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	_, err := diff.parse_patch("--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n")
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Truncated_Hunk))
}

@(test)
test_parse_patch_rejects_multiple_files :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	text := "--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n--- b\n+++ b\n@@ -1 +1 @@\n-x\n+y\n"
	_, err := diff.parse_patch(text)
	testing.expect_value(t, err, diff.Error(diff.Patch_Error.Multiple_Files))
}

@(test)
test_apply_accepts_context_line_with_stripped_space :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// The empty context line lost its leading space, as some editors do.
	result, err := diff.apply("a\n\nb\n", "@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n")
	defer delete(result)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, result, "a\n\nc\n")
}

@(test)
test_apply_preserves_crlf_lines :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "one\r\ntwo\r\n"
	b := "one\r\nzwei\r\n"
	patch, err := diff.unified(a, b)
	defer delete(patch)
	testing.expect_value(t, err, nil)
	result, apply_err := diff.apply(a, patch)
	defer delete(result)
	testing.expect_value(t, apply_err, nil)
	testing.expect_value(t, result, b)
}

@(test)
test_patch_and_unified_survive_allocation_failures :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"
	b := "1\n2\nthree\n4\n5\n6\n7\n8\nnine\n10\n11\n"
	unified_ok, apply_ok := false, false
	for budget in 0 ..< 200 {
		f := Failing_Allocator{context.allocator, budget}
		fa := failing_allocator(&f)
		patch, err := diff.unified(a, b, allocator = fa)
		if err != nil {
			testing.expect_value(t, err, diff.Error(runtime.Allocator_Error.Out_Of_Memory))
			continue
		}
		unified_ok = true
		defer delete(patch)

		f.remaining = budget
		result, apply_err := diff.apply(a, patch, fa)
		if apply_err != nil {
			testing.expect_value(t, apply_err, diff.Error(runtime.Allocator_Error.Out_Of_Memory))
			continue
		}
		apply_ok = true
		testing.expect_value(t, result, b)
		delete(result)
		break
	}
	testing.expect(t, unified_ok && apply_ok, "never succeeded within the allocation budget")
}
