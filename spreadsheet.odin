#+vet explicit-allocators
package vendor_wgpu_example_microui

import "core:fmt"
import "core:hash/xxhash"
import "core:slice"
import "core:strconv"

import mu "vendor:microui"

GRID_COLS :: 10
GRID_ROWS :: 10
CELL_WIDTH :: 110
CELL_HEIGHT :: 24
CELL_BUF_SIZE :: 256

cell_key :: proc(col, row: int) -> string {
	return fmt.tprintf("%c%d", 'A' + col, row + 1)
}

col_label :: proc(col: int) -> string {
	if col < 26 do return fmt.tprintf("%c", 'A' + col)
	return fmt.tprintf("%c%c", 'A' + col / 26 - 1, 'A' + col % 26)
}

Cell :: struct {
	output:      [CELL_BUF_SIZE]byte,
	output_len:  int,
	display_buf: [CELL_BUF_SIZE]byte,
	display_len: int,
	cache_valid: bool,
	cache_value: f64,
	cache_ok:    bool,
	cache_hash:  u64,
}

Cell_Ref :: struct {
	col, row: int,
}

NO_CELL :: Cell_Ref{-1, -1}

Spreadsheet :: struct {
	cells:           [GRID_ROWS][GRID_COLS]Cell,
	edit_buf:        [CELL_BUF_SIZE]byte,
	edit_len:        int,
	editing_cell:    Cell_Ref,
	need_edit_focus: bool,
	edit_textbox_id: mu.Id,
}

UNDO_MAX :: 50

Undo_Entry :: struct {
	col:     int,
	row:     int,
	content: [CELL_BUF_SIZE]byte,
	len:     int,
}

Compute_Context :: struct {
	computing: map[[2]int]bool,
	circular:  bool,
}

precedent_less :: proc(a, b: [2]int) -> bool {
	return a[1] < b[1] || (a[1] == b[1] && a[0] < b[0])
}

// Hash must be stable so cache hits work; cell order in precedents can vary from parse order
hash_precedents :: proc(precedents: [][2]int, own_raw: string) -> u64 {
	h := xxhash.XXH64(transmute([]u8)(own_raw))
	if len(precedents) == 0 do return h
	sorted := make([][2]int, len(precedents), context.temp_allocator)
	copy(sorted, precedents)
	slice.sort_by(sorted, precedent_less)
	for p in sorted {
		raw := get_cell_raw(p[0], p[1])
		bytes := transmute([]u8)(raw)
		h ~= xxhash.XXH64(bytes)
	}
	return h
}

get_cell_value :: proc(cc: ^Compute_Context, col, row: int) -> (value: f64, ok: bool) {
	if col < 0 || col >= GRID_COLS || row < 0 || row >= GRID_ROWS {
		return 0, true
	}
	// Circular refs require early exit
	key := [2]int{col, row}
	if key in cc.computing {
		cc.circular = true
		return 0, false
	}
	cc.computing[key] = true
	defer delete_key(&cc.computing, key)

	raw := get_cell_raw(col, row)
	if len(raw) > 0 && raw[0] == '=' {
		node := parse_formula(raw) or_return
		precedents := collect_precedents(&node) or_return
		precedent_hash := hash_precedents(precedents, raw)
		cell := cell_at_coords(&state.spreadsheet, col, row)
		if cell.cache_valid && cell.cache_hash == precedent_hash {
			return cell.cache_value, cell.cache_ok
		}
		val, eval_ok := eval(node, cc, col, row)
		cell.cache_valid = true
		cell.cache_value = val
		cell.cache_ok = eval_ok
		cell.cache_hash = precedent_hash
		// Upstream change can change our value, so dependents must recompute
		invalidate_dependents(col, row)
		if !eval_ok do return 0, false
		return val, true
	}
	val, _ := strconv.parse_f64(raw)
	return val, true
}

cell_to_display :: proc(col, row: int, cell: ^Cell) -> (result: string, ok: bool) {
	raw := get_cell_raw(col, row)
	if len(raw) == 0 do return "", true
	if raw[0] != '=' do return raw, true

	cc := Compute_Context{}
	res, res_ok := get_cell_value(&cc, col, row)
	if cc.circular do return "#CIRC!", true
	if !res_ok do return "#ERR!", true
	s := fmt.tprintf("%g", res)
	return s, true
}

WINDOW_X :: 20
WINDOW_Y :: 20
WINDOW_W :: 1200
WINDOW_H :: 400
PADDING :: 5
SPACING :: 4
ROW_LABEL_W :: 36

PRECEDENT_COLOR :: mu.Color{100, 150, 255, 128}
DEPENDENT_COLOR :: mu.Color{255, 200, 100, 128}

// Matches microui layout: NO_TITLE so no title bar offset
cell_screen_rect :: proc(col, row: int) -> mu.Rect {
	body_x := i32(WINDOW_X + PADDING)
	body_y := i32(WINDOW_Y + PADDING)
	row_label_and_gap := i32(ROW_LABEL_W + SPACING)
	cell_step_x := i32(CELL_WIDTH + SPACING)
	header_and_gap := i32(CELL_HEIGHT + SPACING)
	row_step_y := i32(CELL_HEIGHT + SPACING)
	return {
		x = body_x + row_label_and_gap + i32(col) * cell_step_x,
		y = body_y + header_and_gap + i32(row) * row_step_y,
		w = i32(CELL_WIDTH),
		h = i32(CELL_HEIGHT),
	}
}

in_bounds :: proc(col, row: int) -> bool {
	return col >= 0 && col < GRID_COLS && row >= 0 && row < GRID_ROWS
}

apply_undo_entry :: proc(entry: ^Undo_Entry) {
	cell := cell_at_coords(&state.spreadsheet, entry.col, entry.row)
	copy(cell.output[:], entry.content[:entry.len])
	cell.output_len = entry.len
	// Output changed, so cached formula result is stale
	cell.cache_valid = false
}

push_undo :: proc(col, row: int, new_content: []byte) {
	if !in_bounds(col, row) do return
	cell := cell_at_coords(&state.spreadsheet, col, row)
	old := cell.output[:cell.output_len]
	// No-op edits would clutter undo stack and break undo/redo expectation
	if len(new_content) <= CELL_BUF_SIZE && slice.equal(old, new_content) do return
	entry: Undo_Entry
	entry.col = col
	entry.row = row
	entry.len = cell.output_len
	copy(entry.content[:], cell.output[:cell.output_len])
	append(&state.undo_stack, entry)
	for len(state.undo_stack) > UNDO_MAX {
		for i in 0 ..< len(state.undo_stack) - 1 {
			state.undo_stack[i] = state.undo_stack[i + 1]
		}
		resize(&state.undo_stack, len(state.undo_stack) - 1)
	}
	// New edit invalidates redo chain
	clear(&state.redo_stack)
}

swap_undo_entry :: proc(from, to: ^[dynamic]Undo_Entry) {
	if len(from) == 0 do return
	entry := pop(from)
	cell := cell_at_coords(&state.spreadsheet, entry.col, entry.row)
	// Mirror captures current state before apply, so redo can undo the undo
	mirror: Undo_Entry
	mirror.col = entry.col
	mirror.row = entry.row
	mirror.len = cell.output_len
	copy(mirror.content[:], cell.output[:cell.output_len])
	append(to, mirror)
	apply_undo_entry(&entry)
}

do_undo :: proc(ctx: ^mu.Context) {
	ec := state.spreadsheet.editing_cell
	// Active edit must be committed first or it would overwrite the undo result
	if cell_ref_valid(ec) {
		commit_edit(ec.col, ec.row, cell_at(&state.spreadsheet, ec))
		stop_editing(ctx)
	}
	if len(state.undo_stack) == 0 do return
	swap_undo_entry(&state.undo_stack, &state.redo_stack)
}

do_redo :: proc(ctx: ^mu.Context) {
	if len(state.redo_stack) == 0 do return
	swap_undo_entry(&state.redo_stack, &state.undo_stack)
}

// Highlights only when user is actively typing; clicking away or on another cell hides them
should_show_dependency_highlights :: proc() -> bool {
	ec := state.spreadsheet.editing_cell
	if !cell_ref_valid(ec) do return false
	return state.mu_ctx.focus_id == state.spreadsheet.edit_textbox_id
}

cell_ref_valid :: proc(ec: Cell_Ref) -> bool {
	return ec.col >= 0 && ec.row >= 0
}

cell_at :: proc(ss: ^Spreadsheet, ec: Cell_Ref) -> ^Cell {
	return &ss.cells[ec.row][ec.col]
}
cell_at_coords :: proc(ss: ^Spreadsheet, col, row: int) -> ^Cell {
	return &ss.cells[row][col]
}

edit_content :: proc() -> []byte {
	n := min(state.spreadsheet.edit_len, CELL_BUF_SIZE)
	return state.spreadsheet.edit_buf[:n]
}

stop_editing :: proc(ctx: ^mu.Context) {
	state.spreadsheet.edit_len = 0
	state.spreadsheet.editing_cell = NO_CELL
	// Clearing focus prevents microui from keeping stale refs to destroyed textbox
	mu.set_focus(ctx, 0)
}

commit_edit :: proc(col, row: int, cell: ^Cell) {
	content := edit_content()
	// Push before applying so undo restores pre-edit state
	push_undo(col, row, content)
	copy(cell.output[:], content)
	cell.output_len = len(content)
	cell.cache_valid = false
}

start_editing :: proc(col, row: int, cell: ^Cell) {
	state.spreadsheet.editing_cell = Cell_Ref{col, row}
	copy(state.spreadsheet.edit_buf[:], cell.output[:cell.output_len])
	state.spreadsheet.edit_len = min(cell.output_len, CELL_BUF_SIZE)
	// Deferred focus
	// textbox not yet created this frame
	// draw_cell will set_focus on next pass
	state.spreadsheet.need_edit_focus = true
}

set_cell :: proc(col, row: int, s: string) {
	if !in_bounds(col, row) do return
	n := min(len(s), CELL_BUF_SIZE)
	cell := cell_at_coords(&state.spreadsheet, col, row)
	copy(cell.output[:], transmute([]byte)(s))
	cell.output_len = n
	cell.cache_valid = false
}

get_cell_raw :: proc(col, row: int) -> string {
	if !in_bounds(col, row) do return ""
	ec := state.spreadsheet.editing_cell
	// Editing cell reads from edit_buf
	// (output not committed until Enter/blur)
	if ec.col == col && ec.row == row do return string(edit_content())
	cell := cell_at_coords(&state.spreadsheet, col, row)
	return string(cell.output[:cell.output_len])
}

get_precedents :: proc(col, row: int) -> (result: [][2]int, result_ok: bool) {
	raw := get_cell_raw(col, row)
	if len(raw) == 0 || raw[0] != '=' do return
	node := parse_formula(raw) or_return
	cells := collect_precedents(&node) or_return
	result_dyn := make([dynamic][2]int, 0, context.temp_allocator)
	// Parser may yield refs like Z99, filter to valid grid range
	for c in cells {
		if in_bounds(c[0], c[1]) do append(&result_dyn, c)
	}
	return result_dyn[:], true
}

get_dependents :: proc(col, row: int) -> (result: [][2]int, result_ok: bool) {
	focused := [2]int{col, row}
	result_dyn := make([dynamic][2]int, 0, context.temp_allocator)
	for r in 0 ..< GRID_ROWS {
		for c in 0 ..< GRID_COLS {
			raw := get_cell_raw(c, r)
			if len(raw) == 0 || raw[0] != '=' do continue
			node := parse_formula(raw) or_continue
			precedents := collect_precedents(&node) or_return
			for p in precedents {
				if p == focused {
					append(&result_dyn, [2]int{c, r})
					break
				}
			}
		}
	}
	return result_dyn[:], true
}

// Dependents must recompute when this cell's cache updates
invalidate_dependents :: proc(col, row: int) {
	deps, ok := get_dependents(col, row)
	if !ok do return
	for d in deps {
		cell_at_coords(&state.spreadsheet, d[0], d[1]).cache_valid = false
	}
}

// Input comes from platform layer (keyboard shortcuts)
// must run before layout so focus/state are correct
handle_pending_actions :: proc(ctx: ^mu.Context, ec: Cell_Ref) {
	ss := &state.spreadsheet
	if state.pending_undo {
		state.pending_undo = false
		do_undo(ctx)
		return
	}
	if state.pending_redo {
		state.pending_redo = false
		do_redo(ctx)
		return
	}
	if !cell_ref_valid(ec) do return
	if state.pending_escape {
		stop_editing(ctx)
		state.pending_escape = false
		return
	}
	if state.pending_copy {
		cell := cell_at(ss, ec)
		text := string(cell.output[:cell.output_len])
		if len(text) > 0 do os_set_clipboard(nil, text)
		state.pending_copy = false
		return
	}
	if state.pending_cut {
		cell := cell_at(ss, ec)
		text := string(cell.output[:cell.output_len])
		if len(text) > 0 do os_set_clipboard(nil, text)
		push_undo(ec.col, ec.row, []byte{})
		cell.output_len = 0
		state.pending_cut = false
		return
	}
	dc, dr := state.pending_cell_nav[0], state.pending_cell_nav[1]
	if dc == 0 && dr == 0 do return
	// Arrow keys: commit current, move to adjacent
	commit_edit(ec.col, ec.row, cell_at(ss, ec))
	nc, nr := ec.col + dc, ec.row + dr
	if nc >= 0 && nc < GRID_COLS && nr >= 0 && nr < GRID_ROWS {
		start_editing(nc, nr, cell_at_coords(ss, nc, nr))
	} else {
		stop_editing(ctx)
	}
	state.pending_cell_nav = {0, 0}
}

draw_cell :: proc(
	ctx: ^mu.Context,
	col, row: int,
	cell: ^Cell,
	ec: Cell_Ref,
	edit_textbox_id: mu.Id,
) {
	ss := &state.spreadsheet
	display, _ := cell_to_display(col, row, cell)
	is_editing := ec.col == col && ec.row == row
	if !is_editing {
		display_id := mu.get_id(ctx, uintptr(&cell.display_buf[0]))
		// Click on display textbox signals "switch to this cell"
		// microui gives us focus before layout
		if ctx.focus_id == display_id {
			if cell_ref_valid(ec) do commit_edit(ec.col, ec.row, cell_at(ss, ec))
			start_editing(col, row, cell)
			is_editing = true
		}
	}
	if is_editing {
		res := mu.textbox(ctx, ss.edit_buf[:], &ss.edit_len, {})
		// set_focus only works after the control exists
		// need_edit_focus set by start_editing
		if ss.need_edit_focus {
			mu.set_focus(ctx, edit_textbox_id)
			ss.need_edit_focus = false
		}
		// Enter commits and moves down
		if .SUBMIT in res {
			commit_edit(col, row, cell)
			next_row := row + 1
			if next_row < GRID_ROWS {
				start_editing(col, next_row, cell_at_coords(ss, col, next_row))
			} else {
				stop_editing(ctx)
			}
		}
	} else {
		copy(cell.display_buf[:], display)
		cell.display_len = min(len(display), CELL_BUF_SIZE)
		// Read-only textbox still receives clicks
		// we detect focus_id above to enter edit mode
		mu.textbox(ctx, cell.display_buf[:], &cell.display_len, {})
	}
}

spreadsheet_ui :: proc(ctx: ^mu.Context) {
	ss := &state.spreadsheet
	if !mu.begin_window(
		ctx,
		"Spreadsheet",
		{WINDOW_X, WINDOW_Y, WINDOW_W, WINDOW_H},
		{.NO_CLOSE, .NO_RESIZE, .NO_TITLE},
	) {
		return
	}

	widths: [GRID_COLS + 1]i32
	widths[0] = i32(ROW_LABEL_W)
	for i in 1 ..< GRID_COLS + 1 {
		widths[i] = CELL_WIDTH
	}

	mu.layout_row(ctx, widths[:], CELL_HEIGHT)
	mu.label(ctx, "")
	for col in 0 ..< GRID_COLS {
		mu.label(ctx, col_label(col))
	}

	ss.edit_textbox_id = mu.get_id(ctx, uintptr(&ss.edit_buf[0]))
	ec := ss.editing_cell
	handle_pending_actions(ctx, ec)
	ec = ss.editing_cell

	// Defocus when focus left edit box (but not if it moved to another cell's display)
	if cell_ref_valid(ec) && !ss.need_edit_focus && ctx.focus_id != ss.edit_textbox_id {
		focus_on_other_cell := false
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				if col == ec.col && row == ec.row {continue}
				c := cell_at_coords(ss, col, row)
				if ctx.focus_id == mu.get_id(ctx, uintptr(&c.display_buf[0])) {
					focus_on_other_cell = true
					break
				}
			}
			if focus_on_other_cell {break}
		}
		// Only commit+defocus when focus left grid; otherwise draw_cell handles the transition
		if !focus_on_other_cell {
			commit_edit(ec.col, ec.row, cell_at(ss, ec))
			stop_editing(ctx)
			ec = NO_CELL
		}
	}

	for row in 0 ..< GRID_ROWS {
		mu.layout_row(ctx, widths[:], CELL_HEIGHT)
		mu.label(ctx, fmt.tprintf("%d", row + 1))
		for col in 0 ..< GRID_COLS {
			draw_cell(ctx, col, row, cell_at_coords(ss, col, row), ec, ss.edit_textbox_id)
		}
	}
	mu.end_window(ctx)
}
