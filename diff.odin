/*
Package diff computes differences between sequences and applies patches.

The core is Eugene Myers' O(ND) difference algorithm with the linear-space
refinement from the same paper: the search finds a "middle snake", splits the
problem in two and recurses, so memory stays proportional to the input size
rather than to its square. The result is a minimal edit script.

On top of the core the package offers line diffs, unified diff output with a
configurable amount of context, a strict unified patch parser and applier, and
a word-level diff for prose.

Every procedure that allocates takes an `allocator` and documents who owns the
result. The package holds no global state, so values are safe to use from one
thread at a time.

Example:
	import "shared:diff"

	main :: proc() {
		patch, err := diff.unified("one\ntwo\n", "one\nthree\n")
		if err != nil {
			return
		}
		defer delete(patch)
	}
*/
package diff

import "base:intrinsics"
import "base:runtime"
import "core:slice"

// Op is the kind of one run in an edit script.
Op :: enum u8 {
	// The run appears in both inputs.
	Equal,
	// The run appears only in the old input, `a`.
	Delete,
	// The run appears only in the new input, `b`.
	Insert,
}

/*
Edit is one run of an edit script.

- For `.Equal`, `a[a_start:][:count]` matches `b[b_start:][:count]`.
- For `.Delete`, `a[a_start:][:count]` is removed; `b_start` is the position
  in `b` where the removed run would have been.
- For `.Insert`, `b[b_start:][:count]` is added; `a_start` is the position in
  `a` where the run goes.

Edit scripts are ordered by position, never contain two adjacent runs with the
same op, never contain empty runs, and list a `.Delete` before the `.Insert`
it pairs with.
*/
Edit :: struct {
	op:      Op,
	a_start: int,
	b_start: int,
	count:   int,
}

// Diff_Error lists the ways the diff procedures can fail before they allocate.
Diff_Error :: enum {
	None,
	// diff_by received a nil equality procedure.
	Nil_Equal_Proc,
}

/*
Error is the compound error type returned by every fallible procedure in this
package. `nil` means success. Compare it against a specific variant, such as
`Diff_Error.Nil_Equal_Proc`, or use a type switch.
*/
Error :: union #shared_nil {
	Diff_Error,
	runtime.Allocator_Error,
}

/*
diff computes a minimal edit script that turns `a` into `b`, comparing
elements with `==`.

Inputs:
- a: the old sequence.
- b: the new sequence.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- edits: the edit script, owned by the caller; free with `delete(edits, allocator)`.
  It is empty when `a` and `b` are both empty.
- err: an allocator error.

Example:
	edits, err := diff.diff([]int{1, 2, 3}, []int{1, 3, 4})
	defer delete(edits)
	// edits: Equal 1, Delete 1, Equal 1, Insert 1
*/
diff :: proc(
	a, b: []$T,
	allocator := context.allocator,
) -> (
	edits: []Edit,
	err: Error,
) where intrinsics.type_is_comparable(T) {
	m := Myers(T) {
		a = a,
		b = b,
	}
	return myers_run(&m, allocator)
}

/*
diff_by computes a minimal edit script that turns `a` into `b`, comparing
elements with `eq`. Use it for element types without `==`, or to compare with
a looser rule such as ignoring case.

Inputs:
- a: the old sequence.
- b: the new sequence.
- eq: returns true when two elements count as equal. It must be consistent:
  the same pair always gives the same answer.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- edits: the edit script, owned by the caller; free with `delete(edits, allocator)`.
- err: `.Nil_Equal_Proc` when `eq` is nil, or an allocator error.
*/
diff_by :: proc(
	a, b: []$T,
	eq: proc(x, y: T) -> bool,
	allocator := context.allocator,
) -> (
	edits: []Edit,
	err: Error,
) {
	if eq == nil {
		return nil, .Nil_Equal_Proc
	}
	m := Myers(T) {
		a  = a,
		b  = b,
		eq = eq,
	}
	return myers_run(&m, allocator)
}

/*
diff_lines computes a minimal edit script between two slices of lines. It
gives the same result as diff on the same input, but first maps every distinct
line to an integer so that each comparison costs one integer compare instead
of a string compare.

Inputs:
- a: the old lines, for example from split_lines.
- b: the new lines.
- allocator: allocates the result and the scratch memory, which is freed
  before returning.

Returns:
- edits: the edit script, owned by the caller; free with `delete(edits, allocator)`.
- err: an allocator error.
*/
diff_lines :: proc(a, b: []string, allocator := context.allocator) -> (edits: []Edit, err: Error) {
	// Reserving up front means the inserts below never allocate.
	ids := make(map[string]int, len(a) + len(b), allocator) or_return
	defer delete(ids)
	a_ids := make([]int, len(a), allocator) or_return
	defer delete(a_ids, allocator)
	b_ids := make([]int, len(b), allocator) or_return
	defer delete(b_ids, allocator)

	intern :: proc(ids: ^map[string]int, line: string) -> int {
		if existing, ok := ids[line]; ok {
			return existing
		}
		id := len(ids)
		ids[line] = id
		return id
	}
	for line, i in a {
		a_ids[i] = intern(&ids, line)
	}
	for line, i in b {
		b_ids[i] = intern(&ids, line)
	}
	return diff(a_ids, b_ids, allocator)
}

/*
edit_counts sums the lengths of the delete and insert runs of `edits`. The sum
of the two is the edit distance that diff minimizes.

Returns:
- deleted: how many elements of `a` the script removes.
- inserted: how many elements of `b` the script adds.
*/
edit_counts :: proc(edits: []Edit) -> (deleted, inserted: int) {
	for e in edits {
		switch e.op {
		case .Equal:
		case .Delete:
			deleted += e.count
		case .Insert:
			inserted += e.count
		}
	}
	return
}

// Myers holds the inputs and scratch state of one diff run.
@(private)
Myers :: struct($T: typeid) {
	a, b:      []T,
	eq:        proc(x, y: T) -> bool,
	a_changed: []bool,
	b_changed: []bool,
	v1, v2:    []int,
}

// myers_same reports whether `m.a[i]` equals `m.b[j]`.
@(private)
myers_same :: #force_inline proc(m: ^Myers($T), i, j: int) -> bool {
	when intrinsics.type_is_comparable(T) {
		if m.eq == nil {
			return m.a[i] == m.b[j]
		}
	}
	return m.eq(m.a[i], m.b[j])
}

// myers_run marks changed elements on both sides, then turns the marks into an edit script.
@(private)
myers_run :: proc(m: ^Myers($T), allocator: runtime.Allocator) -> (edits: []Edit, err: Error) {
	n, mm := len(m.a), len(m.b)

	// One block holds both change maps; the two diagonal vectors share another.
	changed := make([]bool, n + mm, allocator) or_return
	defer delete(changed, allocator)
	m.a_changed = changed[:n]
	m.b_changed = changed[n:]

	v_len := n + mm + 3
	v := make([]int, 2 * v_len, allocator) or_return
	defer delete(v, allocator)
	m.v1 = v[:v_len]
	m.v2 = v[v_len:]

	myers_compare(m, 0, n, 0, mm)
	return edits_from_marks(m.a_changed, m.b_changed, allocator)
}

/*
myers_compare marks the elements of `a[a_lo:a_hi]` and `b[b_lo:b_hi]` that a
minimal edit script changes. It strips the common prefix and suffix, splits
the rest at the middle snake and recurses on both halves. The recursion depth
grows with the logarithm of the edit distance.
*/
@(private)
myers_compare :: proc(m: ^Myers($T), a_lo, a_hi, b_lo, b_hi: int) {
	a_lo, a_hi, b_lo, b_hi := a_lo, a_hi, b_lo, b_hi
	for a_lo < a_hi && b_lo < b_hi && myers_same(m, a_lo, b_lo) {
		a_lo += 1
		b_lo += 1
	}
	for a_lo < a_hi && b_lo < b_hi && myers_same(m, a_hi - 1, b_hi - 1) {
		a_hi -= 1
		b_hi -= 1
	}

	if a_lo == a_hi {
		slice.fill(m.b_changed[b_lo:b_hi], true)
		return
	}
	if b_lo == b_hi {
		slice.fill(m.a_changed[a_lo:a_hi], true)
		return
	}

	x, y, ok := myers_bisect(m, a_lo, a_hi, b_lo, b_hi)
	n, mm := a_hi - a_lo, b_hi - b_lo
	if !ok || (x == 0 && y == 0) || (x == n && y == mm) {
		// The split would not shrink the problem. Marking everything is
		// still a valid script; with the prefix and suffix stripped above
		// the search never takes this path, but the guard keeps the
		// recursion finite no matter what.
		slice.fill(m.a_changed[a_lo:a_hi], true)
		slice.fill(m.b_changed[b_lo:b_hi], true)
		return
	}
	myers_compare(m, a_lo, a_lo + x, b_lo, b_lo + y)
	myers_compare(m, a_lo + x, a_hi, b_lo + y, b_hi)
}

/*
myers_bisect runs the forward and reverse searches of the linear-space Myers
algorithm at the same time until they overlap, and returns the split point
`(x, y)` relative to `(a_lo, b_lo)`. Both inputs must be non-empty.
*/
@(private)
myers_bisect :: proc(m: ^Myers($T), a_lo, a_hi, b_lo, b_hi: int) -> (x, y: int, ok: bool) {
	n := a_hi - a_lo
	mm := b_hi - b_lo
	max_d := (n + mm + 1) / 2
	v_offset := max_d
	v_length := 2 * max_d + 2
	v1 := m.v1[:v_length]
	v2 := m.v2[:v_length]
	slice.fill(v1, -1)
	slice.fill(v2, -1)
	v1[v_offset + 1] = 0
	v2[v_offset + 1] = 0

	delta := n - mm
	// With an odd delta the forward search finds the overlap first;
	// with an even delta the reverse search does.
	front := delta % 2 != 0
	k1_start, k1_end, k2_start, k2_end: int

	for d in 0 ..< max_d {
		// Forward search: furthest reaching d-paths from the top left.
		for k1 := -d + k1_start; k1 <= d - k1_end; k1 += 2 {
			k1_offset := v_offset + k1
			x1: int
			if k1 == -d || (k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1]) {
				x1 = v1[k1_offset + 1]
			} else {
				x1 = v1[k1_offset - 1] + 1
			}
			y1 := x1 - k1
			for x1 < n && y1 < mm && myers_same(m, a_lo + x1, b_lo + y1) {
				x1 += 1
				y1 += 1
			}
			v1[k1_offset] = x1
			if x1 > n {
				// Ran off the right edge of the grid.
				k1_end += 2
			} else if y1 > mm {
				// Ran off the bottom edge of the grid.
				k1_start += 2
			} else if front {
				k2_offset := v_offset + delta - k1
				if k2_offset >= 0 && k2_offset < v_length && v2[k2_offset] != -1 {
					x2 := n - v2[k2_offset]
					if x1 >= x2 {
						return x1, y1, true
					}
				}
			}
		}

		// Reverse search: furthest reaching d-paths from the bottom right.
		for k2 := -d + k2_start; k2 <= d - k2_end; k2 += 2 {
			k2_offset := v_offset + k2
			x2: int
			if k2 == -d || (k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1]) {
				x2 = v2[k2_offset + 1]
			} else {
				x2 = v2[k2_offset - 1] + 1
			}
			y2 := x2 - k2
			for x2 < n && y2 < mm && myers_same(m, a_lo + n - x2 - 1, b_lo + mm - y2 - 1) {
				x2 += 1
				y2 += 1
			}
			v2[k2_offset] = x2
			if x2 > n {
				k2_end += 2
			} else if y2 > mm {
				k2_start += 2
			} else if !front {
				k1_offset := v_offset + delta - k2
				if k1_offset >= 0 && k1_offset < v_length && v1[k1_offset] != -1 {
					x1 := v1[k1_offset]
					y1 := v_offset + x1 - k1_offset
					if x1 >= n - x2 {
						return x1, y1, true
					}
				}
			}
		}
	}
	return 0, 0, false
}

/*
edits_from_marks walks two change maps in step and emits the runs. Deletions
come before insertions at the same position, and adjacent runs never share an
op.
*/
@(private)
edits_from_marks :: proc(a_changed, b_changed: []bool, allocator: runtime.Allocator) -> (edits: []Edit, err: Error) {
	out := make([dynamic]Edit, 0, 8, allocator) or_return
	defer if err != nil {
		delete(out)
	}

	i, j := 0, 0
	n, mm := len(a_changed), len(b_changed)
	for i < n || j < mm {
		e := Edit {
			a_start = i,
			b_start = j,
		}
		switch {
		case i < n && a_changed[i]:
			e.op = .Delete
			for i < n && a_changed[i] {
				i += 1
			}
			e.count = i - e.a_start
		case j < mm && b_changed[j]:
			e.op = .Insert
			for j < mm && b_changed[j] {
				j += 1
			}
			e.count = j - e.b_start
		case:
			e.op = .Equal
			for i < n && j < mm && !a_changed[i] && !b_changed[j] {
				i += 1
				j += 1
			}
			e.count = i - e.a_start
			assert(e.count > 0, "diff: change maps disagree on the number of equal elements")
		}
		append(&out, e) or_return
	}
	shrink(&out) or_return
	return out[:], nil
}
