#+vet explicit-allocators
package vendor_wgpu_example_microui

import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Formula_Range_Op :: enum {
	Sum,
	Average,
	Min,
	Max,
	Count,
}

Formula_Range :: struct {
	cells: [][2]int,
	op:    Formula_Range_Op,
}

Formula_Node :: union {
	Formula_Number,
	Formula_Cell,
	Formula_Binary,
	Formula_Range,
}

Formula_Number :: struct {
	value: f64,
}

Formula_Cell :: struct {
	col: int,
	row: int,
}

Formula_Binary :: struct {
	op:    rune,
	left:  ^Formula_Node,
	right: ^Formula_Node,
}

Formula_Parser :: struct {
	input: string,
	pos:   int,
}

parser_init :: proc(p: ^Formula_Parser, input: string) {
	p.input = strings.trim_space(input)
	p.pos = 0
}

@(require_results)
parser_eof :: proc(p: ^Formula_Parser) -> bool {
	return p.pos >= len(p.input)
}

@(require_results)
parser_peek :: proc(p: ^Formula_Parser) -> (rune, bool) {
	if p.pos >= len(p.input) do return 0, false
	r, _ := utf8.decode_rune_in_string(p.input[p.pos:])
	return r, true
}

@(require_results)
parser_advance :: proc(p: ^Formula_Parser) -> (rune, bool) {
	if p.pos >= len(p.input) do return 0, false
	r, w := utf8.decode_rune_in_string(p.input[p.pos:])
	p.pos += w
	return r, true
}

@(require_results)
parser_skip_ws :: proc(p: ^Formula_Parser) -> bool {
	for !parser_eof(p) && unicode.is_space(parser_peek(p) or_return) {
		_ = parser_advance(p) or_return
	}
	return true
}

@(require_results)
parse_ref_to_col_row :: proc(ref: string) -> (col, row: int, ok: bool) {
	if len(ref) < 2 do return 0, 0, false
	cell_col := 0
	for i in 0 ..< len(ref) {
		c := ref[i]
		if c >= 'A' && c <= 'Z' {
			cell_col = cell_col * 26 + int(c - 'A' + 1)
		} else if c >= 'a' && c <= 'z' {
			cell_col = cell_col * 26 + int(c - 'a' + 1)
		} else {
			row_str := ref[i:]
			cell_row := strconv.parse_int(row_str) or_return
			if cell_row < 1 do return 0, 0, false
			return cell_col - 1, cell_row - 1, true
		}
	}
	return 0, 0, false
}

@(require_results)
parse_cell_ref :: proc(p: ^Formula_Parser) -> (col, row: int, ok: bool) {
	unicode.is_letter(parser_peek(p) or_return) or_return
	start := p.pos
	for !parser_eof(p) && unicode.is_letter(parser_peek(p) or_return) {
		_ = parser_advance(p) or_return
	}
	for !parser_eof(p) && unicode.is_digit(parser_peek(p) or_return) {
		_ = parser_advance(p) or_return
	}
	return parse_ref_to_col_row(p.input[start:p.pos])
}

@(require_results)
parse_cell_or_range :: proc(p: ^Formula_Parser) -> (result: [][2]int, result_ok: bool) {
	c1, r1 := parse_cell_ref(p) or_return
	parser_skip_ws(p) or_return
	if (parser_peek(p) or_return) == ':' {
		_ = parser_advance(p) or_return
		parser_skip_ws(p) or_return
		c2, r2 := parse_cell_ref(p) or_return
		c_min, c_max := min(c1, c2), max(c1, c2)
		r_min, r_max := min(r1, r2), max(r1, r2)
		cells := make([dynamic][2]int, 0, context.temp_allocator)
		for c in c_min ..= c_max {
			for r in r_min ..= r_max {
				append(&cells, [2]int{c, r})
			}
		}
		return cells[:], true
	}
	slice := make([][2]int, 1, context.temp_allocator)
	slice[0] = [2]int{c1, r1}
	return slice, true
}

@(require_results)
parse_range_fn :: proc(
	p: ^Formula_Parser,
	op: Formula_Range_Op,
) -> (
	result: Formula_Node,
	result_ok: bool,
) {
	cells := parse_range_arg(p) or_return
	return Formula_Range{cells = cells, op = op}, true
}

@(require_results)
parse_range_arg :: proc(pp: ^Formula_Parser) -> (result: [][2]int, result_ok: bool) {
	parser_skip_ws(pp) or_return
	if (parser_peek(pp) or_return) != '(' do return nil, false
	_ = parser_advance(pp) or_return
	parser_skip_ws(pp) or_return
	cells := make([dynamic][2]int, 0, context.temp_allocator)
	for !parser_eof(pp) && (parser_peek(pp) or_return) != ')' {
		range_cells, ok := parse_cell_or_range(pp)
		if !ok do return nil, false
		for c in range_cells {
			append(&cells, c)
		}
		parser_skip_ws(pp) or_return
		if (parser_peek(pp) or_return) == ',' {
			_ = parser_advance(pp) or_return
			parser_skip_ws(pp) or_return
		} else if (parser_peek(pp) or_return) != ')' {
			return nil, false
		}
	}
	if (parser_peek(pp) or_return) != ')' do return nil, false
	_ = parser_advance(pp) or_return
	return cells[:], true
}

@(require_results)
parse_factor :: proc(p: ^Formula_Parser) -> (result: Formula_Node, result_ok: bool) {

	parser_skip_ws(p) or_return
	if parser_eof(p) do return nil, false

	r := parser_peek(p) or_return
	if r == '(' {
		_ = parser_advance(p) or_return
		parser_skip_ws(p) or_return
		node := parse_expr(p) or_return
		parser_skip_ws(p) or_return
		if (parser_peek(p) or_return) != ')' do return nil, false
		_ = parser_advance(p) or_return
		return node, true
	}

	if unicode.is_letter(r) {
		start := p.pos
		for !parser_eof(p) && unicode.is_letter(parser_peek(p) or_return) {
			_ = parser_advance(p) or_return
		}
		digits_start := p.pos
		for !parser_eof(p) && unicode.is_digit(parser_peek(p) or_return) {
			_ = parser_advance(p) or_return
		}

		ref := p.input[start:p.pos]
		switch strings.to_lower(ref, context.temp_allocator) {
		case "sum":
			return parse_range_fn(p, .Sum)
		case "avg":
			return parse_range_fn(p, .Average)
		case "min":
			return parse_range_fn(p, .Min)
		case "max":
			return parse_range_fn(p, .Max)
		case "count":
			return parse_range_fn(p, .Count)
		case:
			if digits_start >= p.pos || len(ref) < 2 do return nil, false
			col, row := parse_ref_to_col_row(ref) or_return
			return Formula_Cell{col = col, row = row}, true
		}
	}

	num_start := p.pos
	if r == '-' {
		_ = parser_advance(p) or_return
		parser_skip_ws(p) or_return
		r = parser_peek(p) or_return
	}
	if unicode.is_digit(r) || r == '.' {
		for !parser_eof(p) {
			c := parser_peek(p) or_return
			if unicode.is_digit(c) || c == '.' {
				_ = parser_advance(p) or_return
			} else {
				break
			}
		}
		num_str := p.input[num_start:p.pos]
		val := strconv.parse_f64(num_str) or_return
		n := Formula_Number {
			value = val,
		}
		return n, true
	}

	return nil, false
}

@(require_results)
parse_term :: proc(p: ^Formula_Parser) -> (result: Formula_Node, result_ok: bool) {
	left := parse_factor(p) or_return

	parser_skip_ws(p) or_return
	for !parser_eof(p) {
		r := parser_peek(p) or_return
		if r == '*' || r == '/' {
			_ = parser_advance(p) or_return
			parser_skip_ws(p) or_return
			right := parse_factor(p) or_return
			left_ptr := new_clone(left, context.temp_allocator)
			right_ptr := new_clone(right, context.temp_allocator)
			left = Formula_Binary {
				op    = r,
				left  = left_ptr,
				right = right_ptr,
			}
			parser_skip_ws(p) or_return
		} else {
			break
		}
	}
	return left, true
}

@(require_results)
parse_expr :: proc(p: ^Formula_Parser) -> (result: Formula_Node, result_ok: bool) {
	left := parse_term(p) or_return

	parser_skip_ws(p) or_return
	for !parser_eof(p) {
		r := parser_peek(p) or_return
		if r == '+' || r == '-' {
			_ = parser_advance(p) or_return
			parser_skip_ws(p) or_return
			right := parse_term(p) or_return
			left_ptr := new_clone(left, context.temp_allocator)
			right_ptr := new_clone(right, context.temp_allocator)
			left = Formula_Binary {
				op    = r,
				left  = left_ptr,
				right = right_ptr,
			}
			parser_skip_ws(p) or_return
		} else {
			break
		}
	}
	return left, true
}

@(require_results)
parse_formula :: proc(input: string) -> (result: Formula_Node, result_ok: bool) {
	if len(input) < 2 || input[0] != '=' do return
	parser: Formula_Parser
	parser_init(&parser, input[1:])
	result = parse_expr(&parser) or_return
	parser_skip_ws(&parser) or_return
	if !parser_eof(&parser) do return
	return result, true
}

@(require_results)
collect_precedents :: proc(node: ^Formula_Node) -> (result: [][2]int, result_ok: bool) {
	if node == nil do return
	seen := make(map[[2]int]struct{}, context.temp_allocator)
	collect_impl(node, &seen)
	result_dynamic := make([dynamic][2]int, 0, len(seen), context.temp_allocator)
	for k in seen {
		append(&result_dynamic, k)
	}
	return result_dynamic[:], true
}

collect_impl :: proc(node: ^Formula_Node, seen: ^map[[2]int]struct{}) {
	if node == nil do return
	switch n in node {
	case Formula_Number:
	case Formula_Cell:
		key := [2]int{n.col, n.row}
		seen[key] = {}
	case Formula_Binary:
		collect_impl(n.left, seen)
		collect_impl(n.right, seen)
	case Formula_Range:
		for c in n.cells do seen[c] = {}
	}
}

@(require_results)
eval_range_op :: proc(
	range: Formula_Range,
	cc: ^Compute_Context,
	eval_col, eval_row: int,
) -> (
	value: f64,
	ok: bool,
) {
	values := make([dynamic]f64, 0, context.temp_allocator)
	for c in range.cells {
		if c[0] == eval_col && c[1] == eval_row do continue
		append(&values, get_cell_value(cc, c[0], c[1]) or_return)
	}
	switch range.op {
	case .Sum:
		sum: f64 = 0
		for v in values do sum += v
		return sum, true
	case .Average:
		if len(values) == 0 do return 0, true
		sum: f64 = 0
		for v in values do sum += v
		return sum / f64(len(values)), true
	case .Min:
		if len(values) == 0 do return 0, false
		m := values[0]
		for v in values[1:] do m = min(m, v)
		return m, true
	case .Max:
		if len(values) == 0 do return 0, false
		m := values[0]
		for v in values[1:] do m = max(m, v)
		return m, true
	case .Count:
		return f64(len(values)), true
	case:
		return 0, false
	}
}

@(require_results)
eval :: proc(
	node: Formula_Node,
	cc: ^Compute_Context,
	eval_col, eval_row: int,
) -> (
	value: f64,
	ok: bool,
) {
	if node == nil do return

	switch n in node {
	case Formula_Number:
		return n.value, true
	case Formula_Range:
		return eval_range_op(n, cc, eval_col, eval_row)
	case Formula_Cell:
		if n.col == eval_col && n.row == eval_row do return 0, false
		return get_cell_value(cc, n.col, n.row)
	case Formula_Binary:
		left_val := eval(n.left^, cc, eval_col, eval_row) or_return
		right_val := eval(n.right^, cc, eval_col, eval_row) or_return
		switch n.op {
		case '+':
			return left_val + right_val, true
		case '-':
			return left_val - right_val, true
		case '*':
			return left_val * right_val, true
		case '/':
			if right_val == 0 do return 0, false
			return left_val / right_val, true
		case:
			return 0, false
		}
	}
	return 0, false
}
