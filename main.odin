package vendor_wgpu_example_microui

import "base:runtime"

import mu "vendor:microui"

@(thread_local)
state: struct {
	ctx:              runtime.Context,
	mu_ctx:           mu.Context,
	bg:               mu.Color,
	os:               OS,
	renderer:         Renderer,
	cursor:           [2]i32,
	pending_cell_nav: [2]int,
	pending_copy:     bool,
	pending_cut:      bool,
	pending_escape:   bool,
	pending_undo:     bool,
	pending_redo:     bool,
	spreadsheet:      Spreadsheet,
	undo_stack:       [dynamic]Undo_Entry,
	redo_stack:       [dynamic]Undo_Entry,
}

init_state :: proc() {
	state.ctx = context
	state.bg = {90, 95, 100, 255}
	state.spreadsheet = Spreadsheet {
		editing_cell = {-1, -1},
	}
}

init_default_cells :: proc() {
	set_cell(0, 0, "Val1")
	set_cell(1, 0, "Val2")
	set_cell(2, 0, "Val3")
	set_cell(3, 0, "Add")
	set_cell(4, 0, "Sub")
	set_cell(5, 0, "Mul")
	set_cell(6, 0, "SUM")
	set_cell(7, 0, "AVG")
	set_cell(8, 0, "MIN")
	set_cell(9, 0, "MAX")
	set_cell(0, 1, "100")
	set_cell(1, 1, "50")
	set_cell(2, 1, "25")
	set_cell(3, 1, "=A2+B2")
	set_cell(4, 1, "=A2-B2")
	set_cell(5, 1, "=A2*B2")
	set_cell(6, 1, "=SUM(A2:C2)")
	set_cell(7, 1, "=AVG(A2:C2)")
	set_cell(8, 1, "=MIN(A2:C2)")
	set_cell(9, 1, "=MAX(A2:C2)")
	set_cell(0, 2, "10")
	set_cell(1, 2, "20")
	set_cell(2, 2, "30")
	set_cell(3, 2, "=A3+B3")
	set_cell(4, 2, "=A3-B3")
	set_cell(5, 2, "=A3*B3")
	set_cell(6, 2, "=SUM(A3:C3)")
	set_cell(7, 2, "=AVG(A3:C3)")
	set_cell(8, 2, "=MIN(A3:C3)")
	set_cell(9, 2, "=MAX(A3:C3)")
	set_cell(0, 3, "COUNT")
	set_cell(1, 3, "=COUNT(A2:C3)")
	set_cell(0, 4, "Div")
	set_cell(1, 4, "=A2/B2")
	set_cell(0, 5, "Precedence")
	set_cell(1, 5, "=(A2+B2)*2")
	set_cell(0, 6, "AVG discrete")
	set_cell(1, 6, "=AVG(A2,B3,C2)")
	set_cell(0, 7, "Ref")
	set_cell(1, 7, "=D2")
}

main :: proc() {
	init_state()
	init_default_cells()

	mu.init(&state.mu_ctx, os_set_clipboard, os_get_clipboard, nil)
	state.mu_ctx.text_width = mu.default_atlas_text_width
	state.mu_ctx.text_height = mu.default_atlas_text_height

	os_init()
	r_init_and_run()
}

INSTRUCTIONS :: []string {
	"Formulas: =A1+B1, =SUM(A1:A10), =AVG(A1,B2,C3), =MIN, =MAX, =COUNT",
	"Navigation: Tab / Shift+Tab, Arrow keys",
	"Clipboard: Ctrl+X, Ctrl+C, Ctrl+V",
	"Undo: Ctrl+Z, Redo: Shift+Ctrl+Z/Ctrl+Y",
	"Escape to cancel edit",
	"(For reasons unknown Ctrl+X doens't cut on WASM)",
}

instructions_ui :: proc(ctx: ^mu.Context) {
	if !mu.begin_window(ctx, "Instructions", mu.Rect{20, 440, 450, 250}, {.NO_CLOSE}) {
		return
	}
	for line in INSTRUCTIONS {
		mu.layout_row(ctx, {400}, 20)
		mu.label(ctx, line)
	}
	mu.end_window(ctx)
}

frame :: proc(dt: f32) {
	free_all(context.temp_allocator)

	mc := &state.mu_ctx

	mu.begin(mc)
	spreadsheet_ui(mc)
	instructions_ui(mc)
	mu.end(mc)

	r_render()
}
