package diff_tests

import diff ".."
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

/*
track_begin wraps the current allocator in `tr`. Pair it with
`defer expect_no_leaks(t, tr)` and set `context.allocator` to the result.
*/
track_begin :: proc(tr: ^mem.Tracking_Allocator) -> runtime.Allocator {
	mem.tracking_allocator_init(tr, context.allocator)
	return mem.tracking_allocator(tr)
}

// expect_no_leaks fails the test when `tr` saw a leak or a bad free, then destroys it.
expect_no_leaks :: proc(t: ^testing.T, tr: ^mem.Tracking_Allocator, loc := #caller_location) {
	for _, entry in tr.allocation_map {
		testing.expectf(t, false, "leaked %d bytes allocated at %v", entry.size, entry.location, loc = loc)
	}
	for bad in tr.bad_free_array {
		testing.expectf(t, false, "bad free of %p at %v", bad.memory, bad.location, loc = loc)
	}
	mem.tracking_allocator_destroy(tr)
}

// Failing_Allocator forwards to `backing` until `remaining` allocations have happened, then fails.
Failing_Allocator :: struct {
	backing:   runtime.Allocator,
	remaining: int,
}

failing_allocator :: proc(f: ^Failing_Allocator) -> runtime.Allocator {
	return {procedure = failing_allocator_proc, data = f}
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	f := (^Failing_Allocator)(data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if f.remaining <= 0 {
			return nil, .Out_Of_Memory
		}
		f.remaining -= 1
	}
	return f.backing.procedure(f.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

// Rng is a small deterministic xorshift generator so random tests are reproducible.
Rng :: struct {
	state: u64,
}

rng_next :: proc(r: ^Rng) -> u64 {
	x := r.state
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	r.state = x
	return x
}

// rng_int returns a value in `[0, n)`.
rng_int :: proc(r: ^Rng, n: int) -> int {
	return int(rng_next(r) % u64(n))
}

// random_ints fills a new slice of length `n` with values in `[0, alphabet)`.
random_ints :: proc(r: ^Rng, n, alphabet: int, allocator := context.allocator) -> []int {
	s := make([]int, n, allocator)
	for &x in s {
		x = rng_int(r, alphabet)
	}
	return s
}

// random_text builds `n` lines drawn from a small set, sometimes without a final newline.
random_text :: proc(r: ^Rng, n: int, allocator := context.allocator) -> string {
	words := [?]string{"alpha", "beta", "gamma", "delta", "", "epsilon"}
	sb := strings.builder_make(allocator)
	for i in 0 ..< n {
		strings.write_string(&sb, words[rng_int(r, len(words))])
		if i < n - 1 || rng_int(r, 4) != 0 {
			strings.write_byte(&sb, '\n')
		}
	}
	return strings.to_string(sb)
}

// lcs_length is the O(NM) dynamic programming reference for the longest common subsequence.
lcs_length :: proc(a, b: []int, allocator := context.allocator) -> int {
	prev := make([]int, len(b) + 1, allocator)
	defer delete(prev, allocator)
	cur := make([]int, len(b) + 1, allocator)
	defer delete(cur, allocator)
	for i in 1 ..= len(a) {
		for j in 1 ..= len(b) {
			if a[i - 1] == b[j - 1] {
				cur[j] = prev[j - 1] + 1
			} else {
				cur[j] = max(prev[j], cur[j - 1])
			}
		}
		prev, cur = cur, prev
	}
	return prev[len(b)]
}

/*
expect_valid_script checks every structural promise of an edit script: runs
are non-empty, adjacent runs differ, positions advance in step, equal runs
really match, and the script covers both inputs completely.
*/
expect_valid_script :: proc(t: ^testing.T, a, b: []$T, edits: []diff.Edit, loc := #caller_location) -> bool {
	i, j := 0, 0
	for e, k in edits {
		if !testing.expect(t, e.count > 0, "empty run", loc = loc) {
			return false
		}
		if k > 0 && !testing.expect(t, edits[k - 1].op != e.op, "adjacent runs share an op", loc = loc) {
			return false
		}
		if k > 0 && !testing.expect(t, !(edits[k - 1].op == .Insert && e.op == .Delete), "insert before delete", loc = loc) {
			return false
		}
		if !testing.expect(t, e.a_start == i && e.b_start == j, "run does not start where the last ended", loc = loc) {
			return false
		}
		switch e.op {
		case .Equal:
			for x in 0 ..< e.count {
				if !testing.expect(t, a[i + x] == b[j + x], "equal run does not match", loc = loc) {
					return false
				}
			}
			i += e.count
			j += e.count
		case .Delete:
			i += e.count
		case .Insert:
			j += e.count
		}
	}
	return testing.expect(t, i == len(a) && j == len(b), "script does not cover both inputs", loc = loc)
}
