@tool
class_name StarFocus
extends Node

## Finds the star nearest to the camera's forward direction each frame
## and marks it as focused on the CelestialSphere. Emits a signal when
## focus changes so HUD / audio / chant systems can react.
##
## Attach as a child of your Camera3D (it'll auto-detect), or set `camera`
## and `celestial_sphere` manually. The `focus_angle_deg` tolerance is
## half the apparent size of the "reticle" — 4 degrees feels good for
## mouse-look, bump it to ~8 for gamepad.

@export var celestial_sphere: CelestialSphere

## Camera whose forward direction is used for focus. If null, the parent
## is used if it's a Camera3D.
@export var camera: Camera3D

## Angular tolerance in degrees. A star within this angle of the camera's
## forward vector is considered "focused." Larger = easier to focus but
## more ambiguous when stars are clustered.
@export_range(0.5, 30.0, 0.1) var focus_angle_deg: float = 4.0

## If true, unlearned stars cannot be focused. Turn this on once the
## progression system is wired up so players only interact with stars
## they've discovered via island landfall / chant unlocks. For
## exploration gameplay ("what's that bright one?"), leave it off.
@export var require_learned: bool = false

## Emitted whenever the focused star changes. `star_id` is empty when
## focus is lost. Connect this to your HUD, audio, or quest system.
signal focus_changed(star_id: String)

var _focused_id: String = ""


func _ready() -> void:
	if camera == null:
		var parent := get_parent()
		if parent is Camera3D:
			camera = parent


func _process(_delta: float) -> void:
	if celestial_sphere == null or celestial_sphere.catalog == null or camera == null:
		return

	var fwd: Vector3 = -camera.global_transform.basis.z
	var best_id: String = ""
	# cos of threshold — dot product must exceed this to be "inside" the cone.
	var best_dot: float = cos(deg_to_rad(focus_angle_deg))

	for entry in celestial_sphere.catalog.stars:
		if entry == null:
			continue
		if require_learned and not entry.learned:
			continue
		var dir: Vector3 = celestial_sphere.get_star_direction(entry.id)
		if dir == Vector3.ZERO or dir.y < celestial_sphere.horizon_cutoff:
			continue
		var d: float = fwd.dot(dir)
		if d > best_dot:
			best_dot = d
			best_id = entry.id

	if best_id != _focused_id:
		if _focused_id != "":
			celestial_sphere.highlight(_focused_id, false)
		if best_id != "":
			celestial_sphere.highlight(best_id, true)
		_focused_id = best_id
		focus_changed.emit(best_id)


## Returns the currently-focused star id, or "" if none.
func get_focused_id() -> String:
	return _focused_id


## Returns the currently-focused StarEntry, or null if none.
func get_focused_entry() -> StarEntry:
	if _focused_id == "" or celestial_sphere == null or celestial_sphere.catalog == null:
		return null
	return celestial_sphere.catalog.find_by_id(_focused_id)
