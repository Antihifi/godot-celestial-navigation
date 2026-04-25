class_name BowCompass
extends Node3D

## Diegetic 3D star compass carved into the canoe's bow.
##
## This is the destination UI for star navigation — a physical object on
## the player's boat, not a screen overlay. It reads the same
## CelestialSphere and StarFocus data as the HUD compass, so both can
## coexist and cross-fade during tutorial voyages.
##
## Mental model: imagine a horizontal ring sitting on the prow of the
## canoe with 32 notches carved into it (the historical Polynesian "star
## house" count). As the canoe yaws, the world slides past the ring
## while the ring itself stays locked to the boat. Stars currently
## visible above the horizon appear as glowing points on the ring,
## positioned by their bow-relative azimuth, lifted above the ring plane
## according to their altitude (horizon stars sit on the ring, zenith
## stars float above it). A single label fixed at the bow shows the name
## of whichever traditional 32-house position the canoe is currently aimed
## at (e.g. "Nā Leo Koʻolau" instead of Western N/E/S/W). The focused star
## (from StarFocus) gets a Label3D floating above its marker with the
## Polynesian name.
##
## Setup:
##   Canoe (Node3D)
##   └ BowCompass (this node, positioned on the prow where the ring sits)
##
## Then assign `celestial_sphere`, `catalog`, and (optionally) `star_focus`
## in the inspector. The ring, notches, bow-house label, star markers, and
## focus label are all auto-built at runtime — no scene editing required.
##
## If your canoe model's bow points along +Z instead of -Z (common for
## Blender-imported boats), set `bow_yaw_offset = PI` in the inspector —
## this single knob keeps the bow-house label, `get_star_house()`, and any
## downstream RouteSteering feedback in sync.
##
## The default TorusMesh ring is placeholder art. When you're ready to
## ship, assign a hand-carved wooden ring model to `custom_ring_mesh`
## and the rest of the system keeps working unchanged.

@export var celestial_sphere: CelestialSphere
@export var catalog: StarCatalog
@export var star_focus: StarFocus

## Optional anchor node (Marker3D, BoneAttachment3D, any Node3D) the compass
## snaps to each frame. Let users place the anchor anywhere on their vessel
## (mast top, bow crossbeam, above deck) without needing to reparent this
## node. If unset, BowCompass uses its own transform (default behaviour).
@export var anchor: Node3D

## Optional custom ring mesh. If set, used instead of the procedural
## TorusMesh placeholder. Any mesh centered on its origin and oriented
## with its up axis along +Y will work.
@export var custom_ring_mesh: Mesh

@export_group("Geometry")
## Radius of the compass ring in meters. Tune to match your canoe scale
## — for a typical outrigger, 0.4–0.6 meters feels right.
@export var ring_radius: float = 0.5

## How far above the ring plane a zenith star (altitude = 90°) sits.
## 0 = completely flat ring, larger values = dome-like projection that
## reads altitude at a glance. 0.25 is a nice middle ground.
@export var altitude_scale: float = 0.25

## Number of notches around the ring. 32 is the historical Polynesian
## "star house" count — each house is about 11.25° wide and has a
## traditional name.
@export var notch_count: int = 32

## Every Nth notch is rendered larger to mark cardinal positions in
## the *boat frame* — with `major_notch_every = 8` and `notch_count = 32`,
## the four major notches sit at bow, starboard beam, stern, and port
## beam, which is what you want for a wayfinder's ring.
@export var major_notch_every: int = 8

@export var notch_size: Vector3 = Vector3(0.012, 0.03, 0.028)
@export var star_marker_size: float = 0.03

@export_group("Style")
@export var ring_color: Color = Color(0.32, 0.20, 0.11)
@export var notch_color: Color = Color(0.82, 0.65, 0.38)
@export var major_notch_color: Color = Color(1.0, 0.85, 0.45)
@export var cardinal_color: Color = Color(1.0, 0.92, 0.62)
@export var label_pixel_size: float = 0.0015
@export_range(8, 96, 1) var cardinal_font_size: int = 32
@export_range(8, 96, 1) var focus_font_size: int = 28

@export_group("Behavior")
## Below this altitude (as sin of angle-above-horizon), star markers are
## hidden. Match your CelestialSphere's cutoff for consistency.
@export_range(-0.2, 0.2, 0.005) var horizon_cutoff: float = -0.02

## Y-axis rotation (radians) applied to the compass node's basis each
## frame so its local -Z aligns with the canoe's actual bow direction
## and its local +X aligns with starboard. Godot convention is bow=-Z,
## starboard=+X, but many imported boat models have their bow at +Z
## (Blender exports) — and that often comes paired with a flipped
## starboard axis too. Setting this to PI rotates the entire local
## frame at once, so star bearings, the bow-house label, the
## `get_star_house()` index, and the steering feedback all read
## correctly without any further per-axis hacks.
@export_range(-PI, PI, 0.01) var bow_yaw_offset: float = 0.0

## How much faint / unlearned stars dim relative to learned ones.
@export_range(0.0, 1.0, 0.01) var unlearned_dimming: float = 0.35

## Focused stars get this brightness multiplier.
@export_range(1.0, 5.0, 0.1) var focus_brightness_boost: float = 2.0

## Focused stars get this size multiplier.
@export_range(1.0, 3.0, 0.05) var focus_scale_boost: float = 1.8

## Vertical offset of the focus label above its marker, in meters.
@export var focus_label_offset: float = 0.08


# ---------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------

var _canoe: Node3D
var _ring_instance: MeshInstance3D
var _notches: Array[MeshInstance3D] = []
var _notch_base_colors: Array[Color] = []
var _notch_materials: Array[StandardMaterial3D] = []
var _bow_house_label: Label3D
var _star_markers: Dictionary = {}  # id -> {mesh, mat, entry}
var _focus_label: Label3D
var _star_shader: Shader
var _target_house: int = -1  # -1 = no active target

## Traditional Hawaiian 32-house star compass, arranged clockwise starting
## at true north (house 0). These are the names navigators use for the
## positions where stars rise / set on the horizon — the diegetic
## alternative to N/E/S/W. Houses are world-oriented (fixed to horizon),
## not hull-relative.
const HAWAIIAN_HOUSES := [
	"Haka Koʻolau", "Nā Leo Koʻolau", "Nālani Koʻolau", "Manu Koʻolau",
	"Noio Koʻolau", "ʻĀina Koʻolau", "Lā Koʻolau", "Hikina Koʻolau",
	"Hikina", "Hikina Malanai", "Lā Malanai", "ʻĀina Malanai",
	"Noio Malanai", "Manu Malanai", "Nālani Malanai", "Nā Leo Malanai",
	"Hema", "Nā Leo Kona", "Nālani Kona", "Manu Kona",
	"Noio Kona", "ʻĀina Kona", "Lā Kona", "Komohana Kona",
	"Komohana", "Komohana Hoʻolua", "Lā Hoʻolua", "ʻĀina Hoʻolua",
	"Noio Hoʻolua", "Manu Hoʻolua", "Nālani Hoʻolua", "Nā Leo Hoʻolua",
]

## Color applied to the target-house notch when an active route sets one
## via `set_target_house()`. Intentionally bright so it reads at a glance.
@export var target_notch_color: Color = Color(0.4, 1.0, 0.55)


func _ready() -> void:
	_canoe = _find_canoe()
	_star_shader = _load_star_shader()
	_build_ring()
	_build_notches()
	_build_bow_house_label()
	_build_focus_label()
	_build_star_markers()
	# If no anchor is assigned, _process never overrides our transform, so
	# the bow_yaw_offset rotation has to be baked into our local rotation
	# once at startup. With an anchor, _process applies it every frame.
	if anchor == null and bow_yaw_offset != 0.0:
		rotate_y(bow_yaw_offset)


# ---------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------

## Returns which of the `notch_count` houses a star currently occupies,
## as an integer in [0, notch_count). House 0 is dead ahead (bow), and
## houses increase clockwise when viewed from above (so house
## `notch_count / 4` is the starboard beam, half is astern, and three
## quarters is the port beam).
##
## Returns -1 if the star is below the horizon, unknown, or if the canoe
## can't be found. This is the core wayfinding check — the player's
## "hold Hōkūle'a in house 4" is literally:
##
##     if bow_compass.get_star_house("arcturus") == 4:
##         # on course
##
## Because houses are hull-relative, the answer changes as the canoe
## yaws, which is exactly what makes it a steering instrument rather
## than a compass readout.
func get_star_house(star_id: String) -> int:
	if celestial_sphere == null or _canoe == null:
		return -1
	var dir: Vector3 = celestial_sphere.get_star_direction(star_id)
	if dir == Vector3.ZERO or dir.y < horizon_cutoff:
		return -1
	var canoe_yaw: float = get_canoe_world_yaw()
	var world_az: float = atan2(dir.x, dir.z)
	# Normalize to [0, TAU) so the house index wraps cleanly.
	var rel: float = fposmod(world_az - canoe_yaw, TAU)
	var house_width: float = TAU / float(notch_count)
	# Round rather than floor so stars snap to the nearest house rather
	# than the one they just crossed into — feels more forgiving to steer.
	var idx: int = int(round(rel / house_width)) % notch_count
	return idx


## Highlight a specific house's notch (bow-relative, 0..notch_count-1) as
## the steering target. Call this when the player activates a learned
## route — the lit notch tells them where to aim the guide star.
## Pass -1 (or call `clear_target_house`) to remove the highlight.
func set_target_house(house: int) -> void:
	if house == _target_house:
		return
	# Restore previously-highlighted notch to its base color.
	if _target_house >= 0 and _target_house < _notch_materials.size():
		var prev: StandardMaterial3D = _notch_materials[_target_house]
		var base: Color = _notch_base_colors[_target_house]
		prev.albedo_color = base
		prev.emission = base
		prev.emission_energy_multiplier = 0.5 if (_target_house % major_notch_every) == 0 else 0.25
	_target_house = house
	if house >= 0 and house < _notch_materials.size():
		var mat: StandardMaterial3D = _notch_materials[house]
		mat.albedo_color = target_notch_color
		mat.emission = target_notch_color
		mat.emission_energy_multiplier = 1.5


func clear_target_house() -> void:
	set_target_house(-1)


## Returns the angular error in radians between a star's current bearing
## and the center of a given house. Useful for showing "close, but not
## quite on course" feedback — fade an indicator from red to green as
## this approaches zero. Returns INF if the star isn't visible.
func get_star_house_error(star_id: String, target_house: int) -> float:
	if celestial_sphere == null or _canoe == null:
		return INF
	var dir: Vector3 = celestial_sphere.get_star_direction(star_id)
	if dir == Vector3.ZERO or dir.y < horizon_cutoff:
		return INF
	var canoe_yaw: float = get_canoe_world_yaw()
	var world_az: float = atan2(dir.x, dir.z)
	var rel: float = fposmod(world_az - canoe_yaw, TAU)
	var house_width: float = TAU / float(notch_count)
	var target_center: float = fposmod(float(target_house) * house_width, TAU)
	return _wrap(rel - target_center)


# ---------------------------------------------------------------------
# Build phase
# ---------------------------------------------------------------------

## Walks up the parent chain to find the first Node3D ancestor. Usually
## that's the immediate parent (the canoe), but we walk the chain to be
## robust to being nested under a pivot / mount / anchor Node3D.
## Compute the canoe's bow heading in world space. Reads from the
## compass node's own basis — which `_process` rotates by
## `bow_yaw_offset` each frame — so the value is already correct
## regardless of the canoe model's local-axis convention.
##
## Public so external steering / feedback nodes can compute their own
## hull-relative bearings (e.g. "the star is off your starboard").
func get_canoe_world_yaw() -> float:
	var fwd: Vector3 = -global_transform.basis.z
	return atan2(fwd.x, fwd.z)


func _find_canoe() -> Node3D:
	var p: Node = get_parent()
	while p:
		if p is Node3D and p != self:
			return p
		p = p.get_parent()
	return null


func _load_star_shader() -> Shader:
	var s: Shader = load("res://addons/celestial_nav/star_billboard.gdshader") as Shader
	if s == null:
		var here: String = (get_script() as Script).resource_path.get_base_dir()
		s = load(here + "/star_billboard.gdshader") as Shader
	return s


func _build_ring() -> void:
	_ring_instance = MeshInstance3D.new()
	if custom_ring_mesh:
		_ring_instance.mesh = custom_ring_mesh
	else:
		var mesh := TorusMesh.new()
		mesh.inner_radius = ring_radius - 0.018
		mesh.outer_radius = ring_radius + 0.018
		_ring_instance.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ring_color
		mat.roughness = 0.85
		mat.metallic = 0.0
		_ring_instance.material_override = mat
	_ring_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_instance)


func _build_notches() -> void:
	var minor_mesh := BoxMesh.new()
	minor_mesh.size = notch_size
	var major_mesh := BoxMesh.new()
	major_mesh.size = Vector3(notch_size.x * 1.4, notch_size.y * 1.8, notch_size.z * 1.2)

	for i in range(notch_count):
		# Index 0 is the bow notch, and they proceed clockwise (starboard
		# first) when viewed from above. Aligning i=0 with the bow means
		# major notches naturally land at bow/starboard/stern/port when
		# major_notch_every divides notch_count by 4.
		var angle: float = TAU * float(i) / float(notch_count)
		var is_major: bool = (i % major_notch_every) == 0

		var mi := MeshInstance3D.new()
		mi.mesh = major_mesh if is_major else minor_mesh

		var mat := StandardMaterial3D.new()
		var col: Color = major_notch_color if is_major else notch_color
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.5 if is_major else 0.25
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		mi.transform = Transform3D(
			Basis(Vector3.UP, angle),
			_ring_local_position(angle, 0.0)
		)
		add_child(mi)
		_notches.append(mi)
		_notch_materials.append(mat)
		_notch_base_colors.append(col)


func _build_bow_house_label() -> void:
	_bow_house_label = Label3D.new()
	_bow_house_label.text = ""
	_bow_house_label.font_size = cardinal_font_size
	_bow_house_label.modulate = cardinal_color
	_bow_house_label.pixel_size = label_pixel_size
	_bow_house_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bow_house_label.no_depth_test = true
	_bow_house_label.render_priority = 1
	# Dead ahead, slightly outside the ring.
	_bow_house_label.position = _ring_local_position(0.0, 0.02) * 1.12
	add_child(_bow_house_label)


func _build_focus_label() -> void:
	_focus_label = Label3D.new()
	_focus_label.text = ""
	_focus_label.font_size = focus_font_size
	_focus_label.modulate = Color(1.0, 0.95, 0.7)
	_focus_label.pixel_size = label_pixel_size
	_focus_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_focus_label.no_depth_test = true
	_focus_label.render_priority = 2
	_focus_label.visible = false
	add_child(_focus_label)


func _build_star_markers() -> void:
	if catalog == null or _star_shader == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(star_marker_size, star_marker_size)
	for entry in catalog.stars:
		if entry == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = ring_radius * 4.0

		var mat := ShaderMaterial.new()
		mat.shader = _star_shader
		mat.set_shader_parameter(&"star_color", entry.color)
		mat.set_shader_parameter(&"brightness", entry.brightness)
		mi.material_override = mat

		add_child(mi)
		_star_markers[entry.id] = {
			"mesh": mi,
			"mat": mat,
			"entry": entry,
		}


# ---------------------------------------------------------------------
# Runtime updates
# ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	if celestial_sphere == null or _canoe == null:
		return

	# Snap to anchor node if assigned. Lets users place a Marker3D anywhere
	# on the vessel (mast top, prow, gunwale) and have the compass follow it
	# without reparenting BowCompass itself.
	#
	# After snapping, rotate the basis by `bow_yaw_offset` so the compass's
	# local frame is Godot-standard (-Z=bow, +X=starboard) regardless of
	# how the canoe model was authored. Doing this on the basis (not just
	# adding to a yaw scalar) is what aligns the +X/starboard axis too —
	# fixing the "ring rotates the wrong direction" mirror bug on canoes
	# whose port axis sits where Godot would expect starboard.
	if anchor and is_instance_valid(anchor):
		var t: Transform3D = anchor.global_transform
		if bow_yaw_offset != 0.0:
			t.basis = t.basis.rotated(Vector3.UP, bow_yaw_offset)
		global_transform = t

	# Yaw of the canoe in world space. We rotate world-space star
	# azimuths into this frame so markers sit at their bow-relative
	# bearings on the ring.
	var canoe_yaw: float = get_canoe_world_yaw()

	# --- Bow-house label ---
	# Shows the name of whichever traditional house the bow currently points
	# at in world space. This is the diegetic replacement for the Western
	# cardinal letters: instead of "bow on E by NE", the player reads
	# "bow on Lā Koʻolau".
	if _bow_house_label:
		var bow_house: int = _world_azimuth_to_house(canoe_yaw)
		if bow_house >= 0 and bow_house < HAWAIIAN_HOUSES.size():
			_bow_house_label.text = HAWAIIAN_HOUSES[bow_house]

	# --- Star markers ---
	var focused_id: String = ""
	if star_focus:
		focused_id = star_focus.get_focused_id()
	var focused_marker_pos: Vector3 = Vector3.ZERO
	var focused_entry: StarEntry = null

	for id in _star_markers.keys():
		var data: Dictionary = _star_markers[id]
		var mi: MeshInstance3D = data["mesh"]
		var mat: ShaderMaterial = data["mat"]
		var entry: StarEntry = data["entry"]

		var dir: Vector3 = celestial_sphere.get_star_direction(entry.id)
		if dir == Vector3.ZERO or dir.y < horizon_cutoff:
			mi.visible = false
			continue
		mi.visible = true

		var world_az: float = atan2(dir.x, dir.z)
		var rel: float = _wrap(world_az - canoe_yaw)
		# dir.y is sin(altitude), invariant under yaw, so we use it
		# directly as the vertical lift from the ring plane.
		var lifted: Vector3 = _ring_local_position(rel, dir.y * altitude_scale)
		mi.position = lifted

		var is_focused: bool = id == focused_id
		var scale_mul: float = 1.0
		var brightness_final: float = entry.brightness
		if not entry.learned and not is_focused:
			brightness_final *= unlearned_dimming
		if is_focused:
			scale_mul = focus_scale_boost
			brightness_final *= focus_brightness_boost
			focused_marker_pos = lifted
			focused_entry = entry

		mi.scale = Vector3.ONE * scale_mul
		mat.set_shader_parameter(&"brightness", brightness_final)

	# --- Focus label ---
	if focused_entry != null:
		_focus_label.visible = true
		var star_name: String = focused_entry.display_name
		if star_name == "":
			star_name = focused_entry.id
		_focus_label.text = star_name
		_focus_label.modulate = focused_entry.color
		_focus_label.position = focused_marker_pos + Vector3.UP * focus_label_offset
	else:
		_focus_label.visible = false


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

## Place a point on the ring at bow-relative angle `rel` (0 = ahead,
## +PI/2 = starboard, ±PI = behind, -PI/2 = port) with vertical `lift`.
##
## Note the `-cos` on the Z axis: in Godot, "forward" is local -Z, so
## rel=0 must land at (0, lift, -ring_radius), not (0, lift, +ring_radius).
## Getting this wrong puts your stars behind the boat and is the #1
## thing to check if the compass looks rotated by 180°.
func _ring_local_position(rel: float, lift: float) -> Vector3:
	return Vector3(sin(rel) * ring_radius, lift, -cos(rel) * ring_radius)


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


## Convert a world-space azimuth (radians, 0 = +Z / north, clockwise) into
## a house index in [0, notch_count). Used for the bow-house label — the
## bow's world yaw, fed in here, returns which traditional house the
## canoe is currently aimed at.
func _world_azimuth_to_house(world_az: float) -> int:
	var house_width: float = TAU / float(notch_count)
	var a: float = fposmod(world_az, TAU)
	return int(round(a / house_width)) % notch_count
