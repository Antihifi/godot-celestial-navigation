class_name StarLorePanel
extends Control

## Tapa-cloth styled inspection panel for a focused star.
##
## Draws itself entirely via `_draw()` — no external textures, scenes,
## or theme overrides required. The aesthetic is layered warm-brown
## rectangles with geometric border patterns inspired by Polynesian
## tapa (bark cloth) prints. The panel slides in from the right edge
## of the screen when a star is inspected and slides back out when
## dismissed.
##
## Setup:
##   1. Add under a CanvasLayer (same one as your compass HUD is fine).
##   2. Assign in the StarInspector's `lore_panel` slot.
##   3. Done — the panel starts hidden and is driven entirely by
##      StarInspector calling `show_star()` / `hide_star()`.

@export_group("Layout")
@export var panel_width: float = 380.0
@export var panel_padding: float = 28.0
@export var slide_speed: float = 6.0  # higher = snappier

@export_group("Colors")
## Outer background — darkest layer, the "cloth."
@export var bg_outer: Color = Color(0.12, 0.07, 0.04, 0.92)
## Inner background — slightly lighter, the "field" where text sits.
@export var bg_inner: Color = Color(0.16, 0.10, 0.06, 0.95)
## Border / geometric pattern color.
@export var border_color: Color = Color(0.82, 0.65, 0.38, 0.9)
## Accent color for the star name and decorative elements.
@export var accent_color: Color = Color(1.0, 0.88, 0.55, 1.0)
## Body text color.
@export var text_color: Color = Color(0.92, 0.85, 0.72, 1.0)
## Muted text color for labels ("GUIDE STAR FOR", "LORE", etc.)
@export var label_color: Color = Color(0.65, 0.55, 0.42, 0.85)
## Route text color.
@export var route_color: Color = Color(0.85, 0.78, 0.6, 1.0)

@export_group("Typography")
@export var font_override: Font
@export_range(10, 48, 1) var title_font_size: int = 26
@export_range(8, 32, 1) var subtitle_font_size: int = 16
@export_range(8, 32, 1) var body_font_size: int = 15
@export_range(8, 24, 1) var label_font_size: int = 12

@export_group("Pattern")
## Width of the geometric border band.
@export var border_band_width: float = 14.0
## Size of individual pattern elements (triangles / diamonds).
@export var pattern_cell_size: float = 14.0


# --- State ---
var _entry: StarEntry = null
var _routes: Array = []
var _slide_t: float = 0.0       # 0 = fully hidden, 1 = fully shown
var _target_t: float = 0.0      # where we're animating toward
var _content_height: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true  # always visible — we slide in/out, never toggle


func _process(delta: float) -> void:
	if abs(_slide_t - _target_t) > 0.001:
		_slide_t = lerp(_slide_t, _target_t, clamp(delta * slide_speed, 0.0, 1.0))
		queue_redraw()
	elif _slide_t != _target_t:
		_slide_t = _target_t
		queue_redraw()


# ---------------------------------------------------------------------
# Public API (called by StarInspector)
# ---------------------------------------------------------------------

func show_star(entry: StarEntry, routes: Array = []) -> void:
	_entry = entry
	_routes = routes
	_target_t = 1.0
	queue_redraw()


func hide_star() -> void:
	_target_t = 0.0
	# _entry is kept so the panel can finish its slide-out animation
	# with content still visible — it looks much better than blanking.


# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------

func _draw() -> void:
	if _entry == null and _slide_t < 0.001:
		return
	if _slide_t < 0.001:
		return

	var font: Font = font_override if font_override else get_theme_default_font()
	if font == null:
		return

	var vp_size: Vector2 = size
	var pad: float = panel_padding
	var pw: float = panel_width

	# Slide from right edge. At t=0 the panel is fully off-screen;
	# at t=1 it's flush with the right margin.
	var right_margin: float = 24.0
	var panel_x: float = vp_size.x - (pw + right_margin) * _slide_t + (1.0 - _slide_t) * pw
	var panel_y: float = 80.0  # below any top-of-screen compass HUD

	# We'll accumulate content height as we draw, then use it to size
	# the outer rect. Two-pass would be cleaner but for _draw() a
	# single pass with a generous initial height works fine.
	var cx: float = panel_x + pad           # content left edge
	var cw: float = pw - pad * 2.0          # content width
	var cy: float = panel_y + pad + border_band_width + 8.0  # content top
	var y: float = cy                        # running cursor

	# --- Measure content height first (dry run) ---
	var estimated_h: float = _estimate_content_height(font, cw)
	var panel_h: float = estimated_h + pad * 2.0 + border_band_width * 2.0 + 16.0
	# Clamp to viewport.
	panel_h = min(panel_h, vp_size.y - panel_y - 40.0)

	var outer := Rect2(panel_x, panel_y, pw, panel_h)

	# --- Outer background ---
	draw_rect(outer, bg_outer, true)

	# --- Geometric border band ---
	_draw_tapa_border(outer)

	# --- Inner field ---
	var inner := Rect2(
		panel_x + border_band_width + 4.0,
		panel_y + border_band_width + 4.0,
		pw - (border_band_width + 4.0) * 2.0,
		panel_h - (border_band_width + 4.0) * 2.0,
	)
	draw_rect(inner, bg_inner, true)

	if _entry == null:
		return

	# --- Star color swatch + name ---
	var swatch_size: float = 18.0
	draw_rect(
		Rect2(cx, y + 2.0, swatch_size, swatch_size),
		_entry.color, true
	)
	draw_rect(
		Rect2(cx, y + 2.0, swatch_size, swatch_size),
		border_color, false, 1.5
	)

	# Polynesian name (large).
	var display: String = _entry.display_name if _entry.display_name != "" else _entry.id
	draw_string(
		font,
		Vector2(cx + swatch_size + 10.0, y + title_font_size - 2.0),
		display,
		HORIZONTAL_ALIGNMENT_LEFT,
		int(cw - swatch_size - 10.0),
		title_font_size,
		accent_color
	)
	y += title_font_size + 6.0

	# Scientific name (small, muted).
	if _entry.id != "" and _entry.id != _entry.display_name:
		var sci: String = _entry.id.substr(0, 1).to_upper() + _entry.id.substr(1)
		draw_string(
			font,
			Vector2(cx + swatch_size + 10.0, y + subtitle_font_size - 2.0),
			sci,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(cw - swatch_size - 10.0),
			subtitle_font_size,
			label_color
		)
		y += subtitle_font_size + 4.0

	y += 8.0

	# --- Decorative divider ---
	_draw_divider(cx, y, cw)
	y += 10.0

	# --- Brightness ---
	var brightness_text: String = "Brightness: %s" % _brightness_word(_entry.brightness)
	draw_string(
		font,
		Vector2(cx, y + body_font_size),
		brightness_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		int(cw),
		body_font_size,
		text_color
	)
	y += body_font_size + 10.0

	# --- Learned status ---
	var status_text: String = "Learned" if _entry.learned else "Unknown — not yet in the chant"
	var status_col: Color = accent_color if _entry.learned else label_color
	draw_string(
		font,
		Vector2(cx, y + body_font_size),
		status_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		int(cw),
		body_font_size,
		status_col
	)
	y += body_font_size + 14.0

	# --- Lore ---
	if _entry.lore != "":
		# Label
		draw_string(
			font,
			Vector2(cx, y + label_font_size),
			"LORE",
			HORIZONTAL_ALIGNMENT_LEFT,
			int(cw),
			label_font_size,
			label_color
		)
		y += label_font_size + 6.0

		# Word-wrap the lore text manually.
		y = _draw_wrapped_text(font, cx, y, cw, _entry.lore, body_font_size, text_color)
		y += 10.0

	# --- Routes involving this star ---
	if _routes.size() > 0:
		_draw_divider(cx, y, cw)
		y += 10.0

		draw_string(
			font,
			Vector2(cx, y + label_font_size),
			"GUIDE STAR FOR",
			HORIZONTAL_ALIGNMENT_LEFT,
			int(cw),
			label_font_size,
			label_color
		)
		y += label_font_size + 6.0

		for route in _routes:
			if route == null:
				continue
			var route_text: String = "%s → %s  (house %d at %s)" % [
				route.origin_id, route.destination_id,
				route.target_house,
				_format_hour(route.target_hour),
			]
			y = _draw_wrapped_text(font, cx, y, cw, route_text, body_font_size, route_color)
			y += 6.0


# ---------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------

## Geometric tapa-cloth border: alternating triangles along all four edges.
func _draw_tapa_border(outer: Rect2) -> void:
	var bw: float = border_band_width
	var cs: float = pattern_cell_size
	var col: Color = border_color

	# Top edge
	_draw_triangle_band(
		Vector2(outer.position.x, outer.position.y),
		Vector2(1.0, 0.0),  # direction along edge
		outer.size.x, bw, cs, col, false
	)
	# Bottom edge
	_draw_triangle_band(
		Vector2(outer.position.x, outer.end.y - bw),
		Vector2(1.0, 0.0),
		outer.size.x, bw, cs, col, true
	)
	# Left edge
	_draw_triangle_band(
		Vector2(outer.position.x, outer.position.y + bw),
		Vector2(0.0, 1.0),
		outer.size.y - bw * 2.0, bw, cs, col, false
	)
	# Right edge
	_draw_triangle_band(
		Vector2(outer.end.x - bw, outer.position.y + bw),
		Vector2(0.0, 1.0),
		outer.size.y - bw * 2.0, bw, cs, col, true
	)


func _draw_triangle_band(
	origin: Vector2, dir: Vector2, length: float,
	band_width: float, cell_size: float, col: Color, flip: bool
) -> void:
	# `dir` is the unit vector along the edge. The perpendicular (inward)
	# direction is computed from it.
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	if flip:
		perp = -perp

	var count: int = int(length / cell_size)
	if count < 1:
		return

	var actual_cell: float = length / float(count)
	for i in range(count):
		var base_start: Vector2 = origin + dir * (float(i) * actual_cell)
		var base_end: Vector2 = origin + dir * (float(i + 1) * actual_cell)
		var apex: Vector2 = base_start + dir * (actual_cell * 0.5) + perp * band_width * 0.7

		# Alternate filled / outline for visual rhythm.
		var tri := PackedVector2Array([base_start, base_end, apex])
		if i % 2 == 0:
			draw_colored_polygon(tri, Color(col.r, col.g, col.b, col.a * 0.35))
		draw_polyline(
			PackedVector2Array([base_start, apex, base_end]),
			col, 1.5
		)


func _draw_divider(x: float, y: float, w: float) -> void:
	# A small diamond-chain divider line.
	var col: Color = Color(border_color.r, border_color.g, border_color.b, 0.5)
	draw_line(Vector2(x, y), Vector2(x + w, y), col, 1.0)
	var diamond_count: int = int(w / 16.0)
	if diamond_count < 2:
		return
	var spacing: float = w / float(diamond_count)
	var ds: float = 3.5  # half-size of each diamond
	for i in range(diamond_count):
		var cx: float = x + spacing * (float(i) + 0.5)
		if i % 3 != 0:
			continue
		var diamond := PackedVector2Array([
			Vector2(cx, y - ds),
			Vector2(cx + ds, y),
			Vector2(cx, y + ds),
			Vector2(cx - ds, y),
		])
		draw_colored_polygon(diamond, col)


func _draw_wrapped_text(
	font: Font, x: float, y: float, max_w: float,
	text: String, fsize: int, col: Color
) -> float:
	# Simple greedy word-wrap. Not Unicode-perfect but good enough for
	# English / romanized Polynesian text.
	var words: PackedStringArray = text.split(" ", false)
	var line: String = ""
	var line_h: float = float(fsize) + 4.0

	for word in words:
		var test: String = (line + " " + word).strip_edges() if line != "" else word
		var tw: float = font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if tw > max_w and line != "":
			draw_string(font, Vector2(x, y + fsize), line, HORIZONTAL_ALIGNMENT_LEFT, int(max_w), fsize, col)
			y += line_h
			line = word
		else:
			line = test

	if line != "":
		draw_string(font, Vector2(x, y + fsize), line, HORIZONTAL_ALIGNMENT_LEFT, int(max_w), fsize, col)
		y += line_h

	return y


func _estimate_content_height(font: Font, cw: float) -> float:
	# Rough estimate so we can size the outer rect before drawing.
	# Doesn't need to be pixel-perfect — a few px of padding is fine.
	var h: float = 0.0
	h += title_font_size + 6.0                    # name
	if _entry and _entry.id != _entry.display_name:
		h += subtitle_font_size + 4.0              # scientific name
	h += 8.0                                        # gap
	h += 10.0                                       # divider
	h += body_font_size + 10.0                      # brightness
	h += body_font_size + 14.0                      # learned status
	if _entry and _entry.lore != "":
		h += label_font_size + 6.0                 # "LORE" label
		h += _estimate_wrapped_height(font, cw, _entry.lore, body_font_size)
		h += 10.0
	if _routes.size() > 0:
		h += 10.0                                   # divider
		h += label_font_size + 6.0                 # "GUIDE STAR FOR"
		for route in _routes:
			if route == null:
				continue
			var rt: String = "%s → %s  (house %d at %s)" % [
				route.origin_id, route.destination_id,
				route.target_house, _format_hour(route.target_hour),
			]
			h += _estimate_wrapped_height(font, cw, rt, body_font_size)
			h += 6.0
	return h


func _estimate_wrapped_height(font: Font, max_w: float, text: String, fsize: int) -> float:
	var words: PackedStringArray = text.split(" ", false)
	var line: String = ""
	var line_h: float = float(fsize) + 4.0
	var total: float = 0.0
	for word in words:
		var test: String = (line + " " + word).strip_edges() if line != "" else word
		var tw: float = font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if tw > max_w and line != "":
			total += line_h
			line = word
		else:
			line = test
	if line != "":
		total += line_h
	return total


static func _brightness_word(b: float) -> String:
	if b >= 3.0:
		return "Beacon — unmistakable"
	elif b >= 2.0:
		return "Brilliant"
	elif b >= 1.2:
		return "Bright"
	elif b >= 0.8:
		return "Steady"
	else:
		return "Faint"


static func _format_hour(h: float) -> String:
	var hours: int = int(h)
	var minutes: int = int(fposmod(h, 1.0) * 60.0)
	return "%02d:%02d" % [hours, minutes]
