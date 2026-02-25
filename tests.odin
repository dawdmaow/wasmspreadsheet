package vendor_wgpu_example_microui

import "core:slice"
import "core:testing"

@(test)
parse_ref_a1 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("A1")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 0)
	testing.expect_value(t, row, 0)
}

@(test)
parse_ref_b2 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("B2")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 1)
	testing.expect_value(t, row, 1)
}

@(test)
parse_ref_z1 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("Z1")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 25)
	testing.expect_value(t, row, 0)
}

@(test)
parse_ref_invalid :: proc(t: ^testing.T) {
	_, _, ok := parse_ref_to_col_row("")
	testing.expect_value(t, ok, false)
	_, _, ok2 := parse_ref_to_col_row("1")
	testing.expect_value(t, ok2, false)
}

@(test)
parse_ref_aa1 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("AA1")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 26)
	testing.expect_value(t, row, 0)
}

@(test)
parse_ref_ab1 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("AB1")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 27)
	testing.expect_value(t, row, 0)
}

@(test)
parse_ref_lowercase :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("a1")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 0)
	testing.expect_value(t, row, 0)
}

@(test)
parse_ref_a10 :: proc(t: ^testing.T) {
	col, row, ok := parse_ref_to_col_row("A10")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, col, 0)
	testing.expect_value(t, row, 9)
}

@(test)
parse_ref_a0_invalid :: proc(t: ^testing.T) {
	_, _, ok := parse_ref_to_col_row("A0")
	testing.expect_value(t, ok, false)
}

@(test)
parse_formula_number :: proc(t: ^testing.T) {
	node, ok := parse_formula("=5")
	testing.expect_value(t, ok, true)
	testing.expect(t, node != nil, "parsed node should not be nil")
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 5.0)
}

@(test)
parse_formula_binary :: proc(t: ^testing.T) {
	node, ok := parse_formula("=1+2")
	testing.expect_value(t, ok, true)
	init_state()
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 3.0)
}

@(test)
parse_formula_precedence :: proc(t: ^testing.T) {
	node, ok := parse_formula("=2*3+4")
	testing.expect_value(t, ok, true)
	init_state()
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 10.0)
}

@(test)
parse_formula_invalid :: proc(t: ^testing.T) {
	_, ok := parse_formula("5")
	testing.expect_value(t, ok, false)
	_, ok2 := parse_formula("=1+")
	testing.expect_value(t, ok2, false)
}

@(test)
parse_formula_parentheses :: proc(t: ^testing.T) {
	node, ok := parse_formula("=(1+2)*3")
	testing.expect_value(t, ok, true)
	init_state()
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 9.0)
}

@(test)
parse_formula_negative :: proc(t: ^testing.T) {
	node, ok := parse_formula("=-5")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, -5.0)
}

@(test)
parse_formula_negative_binary :: proc(t: ^testing.T) {
	node, ok := parse_formula("=1+-2")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, -1.0)
}

@(test)
parse_formula_decimal :: proc(t: ^testing.T) {
	node, ok := parse_formula("=3.14")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 3.14)
}

@(test)
parse_formula_avg_min_max_count :: proc(t: ^testing.T) {
	_, ok := parse_formula("=AVG(A1:A3)")
	testing.expect_value(t, ok, true)
	_, ok2 := parse_formula("=MIN(A1:A3)")
	testing.expect_value(t, ok2, true)
	_, ok3 := parse_formula("=MAX(A1:A3)")
	testing.expect_value(t, ok3, true)
	_, ok4 := parse_formula("=COUNT(A1:A3)")
	testing.expect_value(t, ok4, true)
}

@(test)
collect_precedents_single_cell :: proc(t: ^testing.T) {
	node, ok := parse_formula("=A1")
	testing.expect_value(t, ok, true)
	precedents, prec_ok := collect_precedents(&node)
	testing.expect_value(t, prec_ok, true)
	testing.expect_value(t, len(precedents), 1)
	testing.expect_value(t, precedents[0], [2]int{0, 0})
}

@(test)
collect_precedents_multiple :: proc(t: ^testing.T) {
	node, ok := parse_formula("=A1+B2")
	testing.expect_value(t, ok, true)
	precedents, prec_ok := collect_precedents(&node)
	testing.expect_value(t, prec_ok, true)
	slice.sort_by(precedents[:], precedent_less)
	testing.expect_value(t, precedents[0], [2]int{0, 0})
	testing.expect_value(t, precedents[1], [2]int{1, 1})
}

@(test)
collect_precedents_sum_range :: proc(t: ^testing.T) {
	node, ok := parse_formula("=SUM(A1:A3)")
	testing.expect_value(t, ok, true)
	precedents, prec_ok := collect_precedents(&node)
	testing.expect_value(t, prec_ok, true)
	testing.expect_value(t, len(precedents), 3)
}

@(test)
collect_precedents_avg_discrete :: proc(t: ^testing.T) {
	node, ok := parse_formula("=AVG(A1,B2,C3)")
	testing.expect_value(t, ok, true)
	precedents, prec_ok := collect_precedents(&node)
	testing.expect_value(t, prec_ok, true)
	testing.expect_value(t, len(precedents), 3)
	slice.sort_by(precedents[:], precedent_less)
	testing.expect_value(t, precedents[0], [2]int{0, 0})
	testing.expect_value(t, precedents[1], [2]int{1, 1})
	testing.expect_value(t, precedents[2], [2]int{2, 2})
}

@(test)
collect_precedents_sum_plus_cell :: proc(t: ^testing.T) {
	node, ok := parse_formula("=SUM(A1:A2)+B1")
	testing.expect_value(t, ok, true)
	precedents, prec_ok := collect_precedents(&node)
	testing.expect_value(t, prec_ok, true)
	testing.expect_value(t, len(precedents), 3)
	slice.sort_by(precedents[:], precedent_less)
	testing.expect_value(t, precedents[0], [2]int{0, 0})
	testing.expect_value(t, precedents[1], [2]int{1, 0})
	testing.expect_value(t, precedents[2], [2]int{0, 1})
}

@(test)
cell_key_label :: proc(t: ^testing.T) {
	testing.expect_value(t, cell_key(0, 0), "A1")
	testing.expect_value(t, cell_key(1, 0), "B1")
	testing.expect_value(t, col_label(0), "A")
	testing.expect_value(t, col_label(25), "Z")
	testing.expect_value(t, col_label(26), "AA")
	testing.expect_value(t, col_label(27), "AB")
}

@(test)
eval_cell_ref :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "42")
	node, ok := parse_formula("=A1")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 1, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 42.0)
}

@(test)
eval_sum_range :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "1")
	set_cell(0, 1, "2")
	set_cell(0, 2, "3")
	node, ok := parse_formula("=SUM(A1:A3)")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 3)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 6.0)
}

@(test)
eval_average_range :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "2")
	set_cell(0, 1, "4")
	set_cell(0, 2, "6")
	node, ok := parse_formula("=AVG(A1:A3)")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 3)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 4.0)
}

@(test)
eval_min_range :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "5")
	set_cell(0, 1, "1")
	set_cell(0, 2, "9")
	set_cell(1, 0, "=MIN(A1:A3)")
	cc := Compute_Context{}
	val, ok := get_cell_value(&cc, 1, 0)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, val, 1.0)
}

@(test)
eval_max_range :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "5")
	set_cell(0, 1, "1")
	set_cell(0, 2, "9")
	set_cell(1, 0, "=MAX(A1:A3)")
	cc := Compute_Context{}
	val, ok := get_cell_value(&cc, 1, 0)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, val, 9.0)
}

@(test)
eval_count_range :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "7")
	set_cell(0, 1, "8")
	set_cell(0, 2, "9")
	node, ok := parse_formula("=COUNT(A1:A3)")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 3)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 3.0)
}

@(test)
eval_subtract :: proc(t: ^testing.T) {
	node, ok := parse_formula("=10-3")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 7.0)
}

@(test)
eval_divide :: proc(t: ^testing.T) {
	node, ok := parse_formula("=6/2")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 3.0)
}

@(test)
eval_divide_by_zero :: proc(t: ^testing.T) {
	node, ok := parse_formula("=1/0")
	testing.expect_value(t, ok, true)
	_, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, false)
}

@(test)
eval_self_reference :: proc(t: ^testing.T) {
	init_state()
	node, ok := parse_formula("=A1")
	testing.expect_value(t, ok, true)
	_, eval_ok := eval(node, &Compute_Context{}, 0, 0)
	testing.expect_value(t, eval_ok, false)
}

@(test)
eval_mixed_cells :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "3")
	set_cell(1, 0, "4")
	node, ok := parse_formula("=A1*2+B1")
	testing.expect_value(t, ok, true)
	val, eval_ok := eval(node, &Compute_Context{}, 0, 1)
	testing.expect_value(t, eval_ok, true)
	testing.expect_value(t, val, 10.0)
}

@(test)
cell_to_display_raw :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "42")
	display, ok := cell_to_display(0, 0, &state.spreadsheet.cells[0][0])
	testing.expect_value(t, ok, true)
	testing.expect_value(t, display, "42")
}

@(test)
cell_to_display_formula :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "=1+1")
	display, ok := cell_to_display(0, 0, &state.spreadsheet.cells[0][0])
	testing.expect_value(t, ok, true)
	testing.expect_value(t, display, "2")
}

@(test)
cell_to_display_err :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "=1/0")
	display, ok := cell_to_display(0, 0, &state.spreadsheet.cells[0][0])
	testing.expect_value(t, ok, true)
	testing.expect_value(t, display, "#ERR!")
}

@(test)
cell_to_display_circ :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "=B1")
	set_cell(1, 0, "=A1")
	display, ok := cell_to_display(0, 0, &state.spreadsheet.cells[0][0])
	testing.expect_value(t, ok, true)
	testing.expect_value(t, display, "#CIRC!")
}

@(test)
get_precedents_test :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "=B1+C1")
	precedents, ok := get_precedents(0, 0)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, len(precedents), 2)
	slice.sort_by(precedents[:], precedent_less)
	testing.expect_value(t, precedents[0], [2]int{1, 0})
	testing.expect_value(t, precedents[1], [2]int{2, 0})
}

@(test)
get_dependents_test :: proc(t: ^testing.T) {
	init_state()
	set_cell(0, 0, "5")
	set_cell(1, 0, "=A1")
	dependents, ok := get_dependents(0, 0)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, len(dependents), 1)
	testing.expect_value(t, dependents[0], [2]int{1, 0})
}

@(test)
in_bounds_test :: proc(t: ^testing.T) {
	testing.expect_value(t, in_bounds(0, 0), true)
	testing.expect_value(t, in_bounds(-1, 0), false)
	testing.expect_value(t, in_bounds(0, -1), false)
	testing.expect_value(t, in_bounds(GRID_COLS, 0), false)
	testing.expect_value(t, in_bounds(0, GRID_ROWS), false)
}

@(test)
cell_ref_valid_test :: proc(t: ^testing.T) {
	testing.expect_value(t, cell_ref_valid(Cell_Ref{-1, -1}), false)
	testing.expect_value(t, cell_ref_valid(Cell_Ref{0, 0}), true)
}
