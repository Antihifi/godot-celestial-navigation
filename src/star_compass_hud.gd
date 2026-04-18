@tool
class_name StarCompassHUD
extends Control

## A carved-wood horizon strip HUD that shows the canoe's current heading,
## cardinal directions, and the azimuth of every visible star relative to
## the bow. The focused star (via StarFocus) gets a label and a readout
## telling the player how many degrees to port or starboard it sits.
##
## This is a GUI compromise, not a truly diegetic element — real Polynesian
## wayfinders didn't have HUDs. For the shipping game you may want to
## replace this with a 3D carving on the canoe prow and a bowl-of-water
## swell indicator. For now, this gives you something to steer by while
## you build the rest of the navigation gameplay, and the aesthetic is
## carved wood + warm tones so it sits inside the art direction.
##
## Setup:
##   1. Add a CanvasLayer to your scene.
##   2. Add a Control child, attach this script.
##   3. Assign `celestial_sphere`, `canoe` (your player boat Node3D),
##      and `star_focus` in the inspector.
##   4. Done. The strip appears at the top of the screen.

@export var celestial_sphere: CelestialSphere

## The player's canoe / boat root. Its -Z axis is treated as the bow
## (forward). If null, the compass falls back to the camera's yaw so
## you can still see something during early testing.
@export var canoe: Node3D

## Optional — if set, the focused star is labeled and bearing-offset
## readout is shown. Works fine without it.
@export var star_focus: StarFocus

@export_group("Layout")
## Total horizontal arc shown on the strip, in degrees. 140 shows the
## full forward hemisphere with a bit of margin on each side; 180 shows
## exactly ear-to-ear; 360 wraps the whole sky into one strip (busier
## but useful for "where is Hokulea right now" at-a-glance).
@export_range(60.0, 360.0, 1.0) var arc_degrees: float = 140.0
@export var strip_height: float = 56.0
@export var margin_top: float = 28.0
@export var side_margin: float = 48.0

@export_group("Style")
@export var bg_color: Color = Color(0.09, 0.055, 0.03, 0.78)
@export var border_color: Color = Color(0.82, 0.65, 0.38, 0.95)
@export var tick_color: Color = Color(0.82, 0.65, 0.38, 0.85)
@export var cardinal_color: Color = Color(1.0, 0.88, 0.55, 1.0)
@export var bow_color: Color = Color(1.0, 0.92, 0.65, 1.0)
@export var readout_color: Color = Color(0.98, 0.88, 0.62, 1.0)
@export var label_font: Font

## Font size for the focused star label and bearing readout.
@export_range(10, 32, 1) var label_font_size: int = 18

## Font size for cardinal direction letters (N/E/S/W).
@export_range(8, 24, 1) var cardinal_font_size: int = 14


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = strip_height + margin_top + 64.0


func _process(_delta: float) -> void:
	queue_redraw()


func _get_bow_azimuth() -> float:
	if canoe:
		var fwd: Vector3 = -canoe.global_transform.basis.z
		return atan2(fwd.x, fwd.z)
	# Fallback: use the current viewport camera's yaw so we show *something*.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd: Vector3 = -cam.global_transform.basis.z
		return atan2(fwd.x, fwd.z)
	return 0.0


func _draw() -> void:
	if celestial_sphere == null or celestial_sphere.catalog == null:
		return

	var font := label_font if label_font else get_theme_default_font()
	if font == null:
		return

	var width := size.x
	var strip_left := side_margin
	var strip_right := width - side_margin
	var strip_width := strip_right - strip_left
	if strip_width <= 0.0:
		return
	var center_x := (strip_left + strip_right) * 0.5
	var top := margin_top
	var bottom := top + strip_height
	var mid_y := (top + bottom) * 0.5

	var arc_rad: float = deg_to_rad(arc_degrees)
	var half_arc: float = arc_rad * 0.5
	var px_per_rad: float = (strip_width * 0.5) / half_arc

	var bow_az: float = _get_bow_azimuth()

	# --- Strip background ---
	var rect := Rect2(strip_left, top, strip_width, strip_height)
	draw_rect(rect, bg_color, true)
	draw_rect(rect, border_color, false, 2.0)

	# Subtle inner grain lines — cheap "carved wood" feel.
	for i in range(1, 4):
		var y: float = top + strip_height * (float(i) / 4.0)
		draw_line(
			Vector2(strip_left + 6.0, y),
			Vector2(strip_right - 6.0, y),
			Color(border_color.r, border_color.g, border_color.b, 0.08),
			1.0
		)

	# --- Cardinal direction letters (N/E/S/W) ---
	# These sit at fixed world azimuths and slide along the strip as the
	# canoe rotates, giving absolute compass reference.
	var cardinals := {
		"N": 0.0,
		"E": PI * 0.5,
		"S": PI,
		"W": -PI * 0.5,
	}
	for letter in cardinals:
		var world_az: float = cardinals[letter]
		var rel: float = _wrap_angle(world_az - bow_az)
		if abs(rel) > half_arc:
			continue
		var x: float = center_x + rel * px_per_rad
		draw_line(
			Vector2(x, top),
			Vector2(x, bottom),
			Color(cardinal_color.r, cardinal_color.g, cardinal_color.b, 0.25),
			1.0
		)
		var ts: Vector2 = font.get_string_size(
			letter, HORIZONTAL_ALIGNMENT_CENTER, -1, cardinal_font_size
		)
		draw_string(
			font,
			Vector2(x - ts.x * 0.5, top - 6.0),
			letter,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			cardinal_font_size,
			cardinal_color
		)

	# --- Degree tick marks every 15° relative to bow ---
	for deg in range(-180, 181, 15):
		var tick_offset: float = deg_to_rad(float(deg))
		if abs(tick_offset) > half_arc:
			continue
		var x: float = center_x + tick_offset * px_per_rad
		var tick_h: float = 6.0
		if deg % 45 == 0:
			tick_h = 12.0
		draw_line(Vector2(x, bottom), Vector2(x, bottom - tick_h), tick_color, 1.5)

	# --- Stars on the strip ---
	var focused_id := ""
	if star_focus:
		focused_id = star_focus.get_focused_id()
	var focused_rel_deg := INF
	var focused_entry: StarEntry = null

	for entry in celestial_sphere.catalog.stars:
		if entry == null:
			continue
		var dir: Vector3 = celestial_sphere.get_star_direction(entry.id)
		if dir == Vector3.ZERO or dir.y < celestial_sphere.horizon_cutoff:
			continue

		var star_az: float = atan2(dir.x, dir.z)
		var rel: float = _wrap_angle(star_az - bow_az)
		if abs(rel) > half_arc:
			continue

		var x: float = center_x + rel * px_per_rad
		# Place stars vertically based on altitude (dir.y): stars near
		# the horizon sit at the bottom of the strip, stars near zenith
		# float up to the top. Gives the player a crude at-a-glance
		# altitude read without needing a second display.
		var alt_t: float = clamp(dir.y, 0.0, 1.0)
		var y: float = bottom - 6.0 - alt_t * (strip_height - 12.0)

		var is_focused := entry.id == focused_id
		var radius: float = 3.0
		if entry.learned:
			radius = 5.0
		if is_focused:
			radius = 8.0

		var col: Color = entry.color
		if not entry.learned and not is_focused:
			col.a *= 0.4

		draw_circle(Vector2(x, y), radius, col)
		if is_focused:
			draw_arc(Vector2(x, y), radius + 4.0, 0.0, TAU, 32, bow_color, 1.5)
			focused_rel_deg = rad_to_deg(rel)
			focused_entry = entry

	# --- Bow marker (center), drawn over stars so it's always visible ---
	draw_line(
		Vector2(center_x, top - 4.0),
		Vector2(center_x, bottom + 4.0),
		bow_color,
		2.0
	)
	var tri := PackedVector2Array([
		Vector2(center_x, top - 8.0),
		Vector2(center_x - 6.0, top - 18.0),
		Vector2(center_x + 6.0, top - 18.0),
	])
	draw_colored_polygon(tri, bow_color)

	# --- Numeric heading readout below the strip ---
	var bow_deg: float = fposmod(rad_to_deg(bow_az), 360.0)
	var heading_text: String = "HEADING  %03d°" % int(round(bow_deg))
	var hs: Vector2 = font.get_string_size(
		heading_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size
	)
	draw_string(
		font,
		Vector2(center_x - hs.x * 0.5, bottom + 22.0),
		heading_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		label_font_size,
		readout_color
	)

	# --- Focused star label + bearing offset ---
	if focused_entry != null and is_finite(focused_rel_deg):
		var name: String = focused_entry.display_name
		if name == "":
			name = focused_entry.id
		var side: String = "AHEAD"
		var abs_deg: int = int(round(abs(focused_rel_deg)))
		if abs_deg >= 2:
			side = ("%d° STARBOARD" % abs_deg) if focused_rel_deg > 0.0 \
				else ("%d° PORT" % abs_deg)
		var label: String = "%s   —   %s" % [name.to_upper(), side]
		var ls: Vector2 = font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size
		)
		draw_string(
			font,
			Vector2(center_x - ls.x * 0.5, bottom + 46.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			label_font_size,
			focused_entry.color
		)


## Wrap an angle to [-PI, PI]. Godot's built-in `wrapf` does this if you
## pass (-PI, PI) but the behavior at the boundary is subtle, so we
## do it explicitly.
static func _wrap_angle(a: float) -> float:
	return fposmod(a + PI, TAU) - PI
