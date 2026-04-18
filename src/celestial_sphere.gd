@tool
class_name CelestialSphere
extends Node3D

## Renders a set of named, gameplay-meaningful stars in front of Sky3D's
## background starfield and keeps them in sync with Sky3D's time-of-day.
##
## ---------------------------------------------------------------------
## How to set up:
##
## 1. Parent this node to your Camera3D (or to whatever follows the player).
##    The stars are placed on a large sphere centered on this node's origin,
##    so if it tracks the player, they'll look infinitely far away without
##    ever being out of range.
##
## 2. Assign a StarCatalog (.tres) to the `catalog` property.
##
## 3. Assign your Sky3D node (or its TimeOfDay child) to `sky3d_time_source`,
##    and set `sky3d_time_property` to whatever float property on that node
##    exposes the current time in hours (0..24). Sky3D's TimeOfDay node
##    exposes `total_hours` in recent versions — adjust if yours differs.
##
##    If you don't set `sky3d_time_source`, CelestialSphere will use its own
##    `time_of_day_hours` property and you can drive it from anywhere.
##
## 4. Set `latitude_deg` to match the player's current latitude if you want
##    the star compass to shift correctly as they voyage north or south.
##    For a first pass, leaving it at 0 (equator) is fine and gameplay-legible.
## ---------------------------------------------------------------------

## The catalog of stars to render.
@export var catalog: StarCatalog:
	set(value):
		catalog = value
		_dirty = true

## Radius of the star sphere, in meters. Should be larger than your camera's
## typical draw distance but less than its far plane. 4000-8000 is usually
## right — far enough to feel infinite, close enough not to get clipped.
@export var radius: float = 5000.0

## Base size of a star billboard at brightness=1.0, in meters at the
## sphere radius. Scale this if stars look too small or too chunky.
@export var base_star_size: float = 60.0

## Observer latitude in degrees. 0 = equator (Tahiti), +20 = Hawaii-ish,
## -20 = Aotearoa-ish. Drive this from your player's world position if you
## want the star field to shift as they voyage.
@export_range(-90.0, 90.0, 0.1) var latitude_deg: float = 0.0

## If set, CelestialSphere reads time-of-day from this node each frame.
## Point it at your Sky3D or TimeOfDay node.
@export var sky3d_time_source: Node

## Name of the property on `sky3d_time_source` that holds current time in
## hours (0..24). Sky3D's TimeOfDay uses `total_hours`. If you're on an
## older version or a fork, check the inspector and adjust.
@export var sky3d_time_property: StringName = &"total_hours"

## Manual time-of-day in hours. Used when `sky3d_time_source` is null, or
## in the editor for previewing. Wraps at 24.
@export_range(0.0, 24.0, 0.01) var time_of_day_hours: float = 22.0

@export_group("Visibility")
## Stars below this altitude (in units of sin(angle-above-horizon)) are
## hidden. 0.0 = exactly the horizon, negative = slightly below.
## Small negative values let stars peek dramatically from sea level.
@export_range(-0.2, 0.2, 0.005) var horizon_cutoff: float = -0.02

## How much faint / unlearned stars dim relative to learned ones.
@export_range(0.0, 1.0, 0.01) var unlearned_dimming: float = 0.35

@export_group("Highlighting")
## Extra brightness multiplier applied to highlighted stars.
@export_range(1.0, 10.0, 0.1) var highlight_boost: float = 2.5

## Extra size multiplier applied to highlighted stars.
@export_range(1.0, 5.0, 0.1) var highlight_scale: float = 1.6

## Pulse speed for highlighted stars in Hz (0 = no pulse).
@export_range(0.0, 4.0, 0.05) var highlight_pulse_hz: float = 0.6


# ---------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------

var _shader: Shader
var _star_nodes: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _highlighted: Dictionary = {}  # id -> true
var _dirty: bool = true
var _time_accum: float = 0.0


func _ready() -> void:
	_shader = load("res://addons/celestial_nav/star_billboard.gdshader") as Shader
	if _shader == null:
		# Fall back to a sibling path if the user dropped the files
		# somewhere other than addons/celestial_nav/.
		_shader = load((get_script() as Script).resource_path.get_base_dir() + "/star_billboard.gdshader") as Shader
	_rebuild_if_needed()


func _process(delta: float) -> void:
	_time_accum += delta
	_rebuild_if_needed()

	# Pull time from Sky3D if connected.
	if sky3d_time_source and sky3d_time_property in sky3d_time_source:
		var t = sky3d_time_source.get(sky3d_time_property)
		if t is float or t is int:
			time_of_day_hours = fposmod(float(t), 24.0)

	_update_star_transforms()


# ---------------------------------------------------------------------
# Public API — call these from your gameplay code
# ---------------------------------------------------------------------

## Mark a star as currently highlighted (glowing, pulsing, enlarged).
## Useful when the player "focuses" on a star through a diegetic UI, or
## when a chant stanza references it.
func highlight(star_id: String, on: bool = true) -> void:
	if on:
		_highlighted[star_id] = true
	else:
		_highlighted.erase(star_id)


## Clear all highlights.
func clear_highlights() -> void:
	_highlighted.clear()


## Returns the current world-space direction of a star (unit vector),
## or Vector3.ZERO if unknown. Useful for "am I pointed at this star?"
## checks without needing to raycast against the billboard.
func get_star_direction(star_id: String) -> Vector3:
	if catalog == null:
		return Vector3.ZERO
	var entry := catalog.find_by_id(star_id)
	if entry == null:
		return Vector3.ZERO
	return _celestial_basis() * entry.get_celestial_direction()


## Returns the azimuth (compass bearing in radians, 0 = +Z / north,
## increasing clockwise toward +X / east) where a star currently sits,
## or INF if it's below the horizon or unknown. Use `is_finite(result)`
## to test visibility — a valid azimuth can be any value in [-PI, PI],
## so we can't use -1.0 or similar as a sentinel.
func get_star_azimuth(star_id: String) -> float:
	var dir := get_star_direction(star_id)
	if dir == Vector3.ZERO or dir.y < horizon_cutoff:
		return INF
	return atan2(dir.x, dir.z)


## Returns true if the star exists and is currently above the horizon.
func is_star_visible(star_id: String) -> bool:
	var dir := get_star_direction(star_id)
	return dir != Vector3.ZERO and dir.y >= horizon_cutoff


# ---------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------

## Build the rotation basis that takes a star from its fixed celestial
## frame (pole = +Y) into world space for the current time and latitude.
##
## The math: stars are fixed on a sphere that rotates once per day around
## the celestial pole. The pole's direction in world space depends on the
## observer's latitude — at the equator it sits on the horizon pointing
## north, at the poles it points straight up. So:
##
##   1. Rotate the star around the pole (local +Y) by the current hour angle.
##   2. Tilt the whole frame so +Y aligns with the observer's celestial pole.
##
## This is a simplification of real celestial mechanics but it's correct
## enough to be navigationally learnable, which is all the gameplay needs.
func _celestial_basis() -> Basis:
	# Full rotation every 24 in-game hours. Negative so stars rise in the
	# east (+X) and set in the west (-X) with our coordinate convention.
	var hour_angle := -(time_of_day_hours / 24.0) * TAU
	var daily := Basis(Vector3.UP, hour_angle)

	# At latitude φ, the celestial pole sits φ degrees above the northern
	# horizon. We start with the pole at +Y (straight up) and tilt it
	# backward around the east-west (X) axis by (90° - φ).
	var pole_tilt_angle := deg_to_rad(latitude_deg - 90.0)
	var pole_tilt := Basis(Vector3.RIGHT, pole_tilt_angle)

	return pole_tilt * daily


func _rebuild_if_needed() -> void:
	if not _dirty:
		return
	_dirty = false

	for n in _star_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_star_nodes.clear()
	_materials.clear()

	if catalog == null or _shader == null:
		return

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	for entry in catalog.stars:
		if entry == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = radius  # Prevent frustum-culling at sphere edge.

		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter(&"star_color", entry.color)
		mat.set_shader_parameter(&"brightness", entry.brightness)
		mi.material_override = mat

		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
		_star_nodes.append(mi)
		_materials.append(mat)


func _update_star_transforms() -> void:
	if catalog == null or _star_nodes.size() != catalog.stars.size():
		return

	var basis := _celestial_basis()
	var pulse := 1.0 + 0.25 * sin(_time_accum * TAU * highlight_pulse_hz)

	for i in range(_star_nodes.size()):
		var entry: StarEntry = catalog.stars[i]
		var mi: MeshInstance3D = _star_nodes[i]
		var mat: ShaderMaterial = _materials[i]
		if entry == null or mi == null:
			continue

		var dir := basis * entry.get_celestial_direction()

		# Hide below horizon. This is cheap and avoids the "stars under
		# the sea" problem when the player looks down at the water.
		if dir.y < horizon_cutoff:
			mi.visible = false
			continue
		mi.visible = true

		# Position on sphere.
		mi.position = dir * radius

		# Size: scale with radius so angular size stays constant, boosted
		# by brightness, and again by highlight state.
		var size := base_star_size * sqrt(entry.brightness)
		var is_highlighted: bool = _highlighted.has(entry.id)
		if is_highlighted:
			size *= highlight_scale * pulse

		# Fade stars near the horizon so they don't pop in harshly.
		var horizon_fade := clamp((dir.y - horizon_cutoff) / 0.1, 0.0, 1.0)

		# Dim unlearned stars so the sky is populated but they don't
		# distract from the ones the player knows.
		var learned_mul: float = 1.0 if entry.learned else unlearned_dimming
		if is_highlighted:
			learned_mul = max(learned_mul, 1.0)

		var brightness_final: float = entry.brightness * learned_mul * horizon_fade
		if is_highlighted:
			brightness_final *= highlight_boost * pulse

		mi.scale = Vector3.ONE * size
		mat.set_shader_parameter(&"brightness", brightness_final)
