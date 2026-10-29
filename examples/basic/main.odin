// Example basic diffs two texts, applies the patch and shows a word diff. Run it with `odin run examples/basic`.
package main

import diff "../.."
import "core:fmt"
import "core:os"

main :: proc() {
	old_text := "milk\neggs\nbread\nbutter\n"
	new_text := "milk\neggs\nsourdough bread\nbutter\njam\n"

	// A unified diff, as `diff -u` prints it.
	patch, err := diff.unified(old_text, new_text, "list.txt", "list.txt")
	if err != nil {
		fmt.eprintln("unified failed:", err)
		os.exit(1)
	}
	defer delete(patch)
	fmt.print(patch)

	// Applying the patch to the old text gives back the new text.
	patched, apply_err := diff.apply(old_text, patch)
	if apply_err != nil {
		fmt.eprintln("apply failed:", apply_err)
		os.exit(1)
	}
	defer delete(patched)
	fmt.println("round trip ok:", patched == new_text)

	// A word diff for prose.
	words, words_err := diff.diff_words("the quick brown fox", "the slow brown fox jumps")
	if words_err != nil {
		fmt.eprintln("diff_words failed:", words_err)
		os.exit(1)
	}
	defer delete(words)
	inline, format_err := diff.format_word_diff(words)
	if format_err != nil {
		fmt.eprintln("format_word_diff failed:", format_err)
		os.exit(1)
	}
	defer delete(inline)
	fmt.println(inline)

	// The generic core works on any slice.
	edits, edits_err := diff.diff([]int{1, 2, 3, 4}, []int{1, 3, 4, 5})
	if edits_err != nil {
		fmt.eprintln("diff failed:", edits_err)
		os.exit(1)
	}
	defer delete(edits)
	for e in edits {
		fmt.printfln("%v a[%d:] b[%d:] x%d", e.op, e.a_start, e.b_start, e.count)
	}
}
