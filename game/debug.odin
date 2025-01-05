package game

import rl "vendor:raylib"

Debug_Rect_Shape :: struct {
	rec:        rl.Rectangle,
	line_thick: f32,
	color:      rl.Color,
}

Debug_Line_Shape :: struct {
	start_pos, end_pos: rl.Vector2,
	line_thick:         f32,
	color:              rl.Color,
}

Debug_Circle_Shape :: struct {
	center: rl.Vector2,
	radius: f32,
	color:  rl.Color,
}

Debug_Shapes :: union {
	Debug_Rect_Shape,
	Debug_Circle_Shape,
	Debug_Line_Shape,
}

draw_debug_rec :: proc(rec: rl.Rectangle, line_thick: f32, color: rl.Color) {
	append(&g_mem.debug_shapes, Debug_Rect_Shape{rec, line_thick, color})
}

draw_debug_line :: proc(start_pos, end_pos: rl.Vector2, line_thick: f32, color: rl.Color) {
	append(&g_mem.debug_shapes, Debug_Line_Shape{start_pos, end_pos, line_thick, color})
}

draw_debug_circle :: proc(center: rl.Vector2, radius: f32, color: rl.Color) {
	append(&g_mem.debug_shapes, Debug_Circle_Shape{center, radius, color})
}

draw_debug_shapes :: proc() {
	for &s in g_mem.debug_shapes {
		#partial switch ds in s {
		case Debug_Circle_Shape:
			rl.DrawCircleLinesV(ds.center, ds.radius, ds.color)
		case Debug_Line_Shape:
			rl.DrawLineEx(ds.start_pos, ds.end_pos, ds.line_thick, ds.color)
		case Debug_Rect_Shape:
			rl.DrawRectangleLinesEx(ds.rec, ds.line_thick, ds.color)
		}
	}
}
