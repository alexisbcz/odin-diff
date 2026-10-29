// Package diff_tests holds the unit tests for diff. Run them with `odin test tests`.
package diff_tests

import diff ".."
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

@(test)
test_diff_both_empty_gives_empty_script :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff([]int{}, []int{})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(edits), 0)
}

@(test)
test_diff_empty_old_is_one_insert :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff([]int{}, []int{1, 2, 3})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 1) {
		testing.expect_value(t, edits[0], diff.Edit{.Insert, 0, 0, 3})
	}
}

@(test)
test_diff_empty_new_is_one_delete :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff([]int{1, 2}, []int{})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 1) {
		testing.expect_value(t, edits[0], diff.Edit{.Delete, 0, 0, 2})
	}
}

@(test)
test_diff_identical_is_one_equal_run :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []int{4, 5, 6, 7}
	edits, err := diff.diff(a, a)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 1) {
		testing.expect_value(t, edits[0], diff.Edit{.Equal, 0, 0, 4})
	}
}

@(test)
test_diff_single_substitution :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []int{1, 2, 3}
	b := []int{1, 9, 3}
	edits, err := diff.diff(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	want := []diff.Edit{{.Equal, 0, 0, 1}, {.Delete, 1, 1, 1}, {.Insert, 2, 1, 1}, {.Equal, 2, 2, 1}}
	if testing.expect_value(t, len(edits), len(want)) {
		for e, i in want {
			testing.expect_value(t, edits[i], e)
		}
	}
}

@(test)
test_diff_myers_paper_example_has_distance_five :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// The running example from Myers (1986): ABCABBA to CBABAC needs 5 edits.
	a := utf8.string_to_runes("ABCABBA")
	defer delete(a)
	b := utf8.string_to_runes("CBABAC")
	defer delete(b)
	edits, err := diff.diff(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	expect_valid_script(t, a, b, edits)
	deleted, inserted := diff.edit_counts(edits)
	testing.expect_value(t, deleted + inserted, 5)
}

@(test)
test_diff_disjoint_inputs_delete_then_insert :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	edits, err := diff.diff([]int{1, 2, 3}, []int{7, 8})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 2) {
		testing.expect_value(t, edits[0], diff.Edit{.Delete, 0, 0, 3})
		testing.expect_value(t, edits[1], diff.Edit{.Insert, 3, 0, 2})
	}
}

@(test)
test_diff_keeps_common_prefix_and_suffix :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []int{1, 2, 3, 4, 5}
	b := []int{1, 2, 4, 5}
	edits, err := diff.diff(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	want := []diff.Edit{{.Equal, 0, 0, 2}, {.Delete, 2, 2, 1}, {.Equal, 3, 2, 2}}
	if testing.expect_value(t, len(edits), len(want)) {
		for e, i in want {
			testing.expect_value(t, edits[i], e)
		}
	}
}

@(test)
test_diff_pure_insertion_in_middle :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []int{1, 4}
	b := []int{1, 2, 3, 4}
	edits, err := diff.diff(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	want := []diff.Edit{{.Equal, 0, 0, 1}, {.Insert, 1, 1, 2}, {.Equal, 1, 3, 1}}
	if testing.expect_value(t, len(edits), len(want)) {
		for e, i in want {
			testing.expect_value(t, edits[i], e)
		}
	}
}

@(test)
test_diff_random_inputs_are_minimal :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	rng := Rng{0x9e3779b97f4a7c15}
	for round in 0 ..< 600 {
		alphabet := 2 + round % 5
		a := random_ints(&rng, rng_int(&rng, 40), alphabet)
		defer delete(a)
		b := random_ints(&rng, rng_int(&rng, 40), alphabet)
		defer delete(b)

		edits, err := diff.diff(a, b)
		defer delete(edits)
		if !testing.expect_value(t, err, nil) {
			return
		}
		if !expect_valid_script(t, a, b, edits) {
			return
		}
		deleted, inserted := diff.edit_counts(edits)
		lcs := lcs_length(a, b)
		if !testing.expectf(t, deleted == len(a) - lcs && inserted == len(b) - lcs, "round %d: not minimal: %v vs %v", round, a, b) {
			return
		}
	}
}

@(test)
test_diff_large_input_with_few_changes :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	N :: 50_000
	a := make([]int, N)
	defer delete(a)
	for &x, i in a {
		x = i
	}
	b := make([dynamic]int, 0, N + 10)
	defer delete(b)
	for x in a {
		switch {
		case x % 10_000 == 5:
			// Deleted.
		case x % 10_000 == 7:
			append(&b, -x, x)
		case:
			append(&b, x)
		}
	}

	edits, err := diff.diff(a, b[:])
	defer delete(edits)
	testing.expect_value(t, err, nil)
	expect_valid_script(t, a, b[:], edits)
	deleted, inserted := diff.edit_counts(edits)
	testing.expect_value(t, deleted, 5)
	testing.expect_value(t, inserted, 5)
}

@(test)
test_diff_completely_different_large_inputs :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	// The worst case for O(ND): nothing in common.
	N :: 2_000
	a := make([]int, N)
	defer delete(a)
	b := make([]int, N)
	defer delete(b)
	for i in 0 ..< N {
		a[i] = i
		b[i] = N + i
	}
	edits, err := diff.diff(a, b)
	defer delete(edits)
	testing.expect_value(t, err, nil)
	deleted, inserted := diff.edit_counts(edits)
	testing.expect_value(t, deleted, N)
	testing.expect_value(t, inserted, N)
}

@(test)
test_diff_by_ignores_case :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []string{"Hello", "World"}
	b := []string{"hello", "world", "again"}
	edits, err := diff.diff_by(a, b, proc(x, y: string) -> bool {
		return strings.equal_fold(x, y)
	})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(edits), 2) {
		testing.expect_value(t, edits[0], diff.Edit{.Equal, 0, 0, 2})
		testing.expect_value(t, edits[1], diff.Edit{.Insert, 2, 2, 1})
	}
}

@(test)
test_diff_by_rejects_nil_proc :: proc(t: ^testing.T) {
	edits, err := diff.diff_by([]int{1}, []int{2}, nil)
	testing.expect_value(t, err, diff.Error(diff.Diff_Error.Nil_Equal_Proc))
	testing.expect_value(t, len(edits), 0)
}

// Record has a slice field, so it has no `==` and needs diff_by.
Record :: struct {
	key:  int,
	tags: []string,
}

@(test)
test_diff_by_works_on_types_without_equality :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []Record{{1, nil}, {2, nil}, {3, nil}}
	b := []Record{{1, nil}, {3, nil}}
	edits, err := diff.diff_by(a, b, proc(x, y: Record) -> bool {
		return x.key == y.key
	})
	defer delete(edits)
	testing.expect_value(t, err, nil)
	deleted, inserted := diff.edit_counts(edits)
	testing.expect_value(t, deleted, 1)
	testing.expect_value(t, inserted, 0)
}

@(test)
test_diff_lines_matches_generic_diff :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	rng := Rng{12345}
	for _ in 0 ..< 100 {
		a_text := random_text(&rng, rng_int(&rng, 30))
		defer delete(a_text)
		b_text := random_text(&rng, rng_int(&rng, 30))
		defer delete(b_text)
		a, _ := diff.split_lines(a_text)
		defer delete(a)
		b, _ := diff.split_lines(b_text)
		defer delete(b)

		fast, err1 := diff.diff_lines(a, b)
		defer delete(fast)
		slow, err2 := diff.diff(a, b)
		defer delete(slow)
		testing.expect_value(t, err1, nil)
		testing.expect_value(t, err2, nil)
		if !testing.expect_value(t, len(fast), len(slow)) {
			return
		}
		for e, i in fast {
			testing.expect_value(t, e, slow[i])
		}
	}
}

@(test)
test_edit_counts_sums_changes :: proc(t: ^testing.T) {
	edits := []diff.Edit{{.Equal, 0, 0, 3}, {.Delete, 3, 3, 2}, {.Insert, 5, 3, 4}, {.Equal, 5, 7, 1}, {.Insert, 6, 8, 1}}
	deleted, inserted := diff.edit_counts(edits)
	testing.expect_value(t, deleted, 2)
	testing.expect_value(t, inserted, 5)

	none_deleted, none_inserted := diff.edit_counts(nil)
	testing.expect_value(t, none_deleted, 0)
	testing.expect_value(t, none_inserted, 0)
}

@(test)
test_diff_out_of_memory_reports_error_without_leaking :: proc(t: ^testing.T) {
	tr: mem.Tracking_Allocator
	context.allocator = track_begin(&tr)
	defer expect_no_leaks(t, &tr)

	a := []int{1, 2, 3, 4, 5, 6, 7, 8}
	b := []int{1, 3, 4, 9, 6, 7, 8, 10}
	for budget in 0 ..< 20 {
		f := Failing_Allocator{context.allocator, budget}
		edits, err := diff.diff(a, b, failing_allocator(&f))
		if err == nil {
			expect_valid_script(t, a, b, edits)
			delete(edits)
			return
		}
		testing.expect_value(t, err, diff.Error(runtime.Allocator_Error.Out_Of_Memory))
		testing.expect_value(t, len(edits), 0)
	}
	testing.expect(t, false, "diff never succeeded")
}
