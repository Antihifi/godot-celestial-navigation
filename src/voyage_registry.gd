class_name VoyageRegistry
extends Node

## The bridge between procedural islands and the star navigation system.
##
## THE KEY IDEA: stars do not point to islands. They point to routes
## between islands. This registry holds (a) the canonical positions of
## islands the player has committed to via a moai, and (b) the learned
## routes between them, each represented as a Route resource ("at hour
## Z, hold star X in house Y"). Guide stars are computed *per route*,
## at registration time, by scanning the catalog for whichever visible
## star best aligns with the required bearing at a plausible hour.
##
## Workflow:
##   1. Player places first moai     → register_moai("tahiti", pos)
##   2. Player explores, lands new   → register_discovery("tahiti", landing_pos)
##   3. Player places second moai    → register_moai("hawaii", pos)
##                                      (converts matching discoveries
##                                       into learned Routes, fires
##                                       `route_learned` signal)
##   4. Player wants to go back      → learned_route("tahiti","hawaii")
##   5. Steering feedback each frame → route.is_on_course(
##                                        bow_compass.get_star_house(
##                                          route.guide_star_id),
##                                        bow_compass.notch_count)
##
## Save/load: `_beacons`, `_pending`, and `_routes` are the full
## persistent state. Serialize them as a dict and you're done.

signal moai_registered(island_id: String, position: Vector3)
signal discovery_recorded(origin_id: String, landing_pos: Vector3)
signal route_learned(route: Route)

@export var celestial_sphere: CelestialSphere

## Must match BowCompass.notch_count. If you change one, change both.
@export var notch_count: int = 32

## Hours of night the registry scans when picking a guide star for a
## new route. More hours = better alignments found, more compute.
## These are "typical voyaging hours" — we don't bother with daytime
## since you can't see stars then anyway.
@export var candidate_hours: PackedFloat32Array = PackedFloat32Array([20.0, 22.0, 0.0, 2.0, 4.0])

## Max distance between a pending discovery's landing point and a
## newly-built moai for them to be counted as the same island. Generous
## by default — your procedural islands won't exceed this easily.
@export var moai_discovery_match_radius: float = 2000.0

## Optional latitude override applied while computing routes. If
## negative, the registry uses celestial_sphere.latitude_deg as-is.
## For a compressed-Pacific game you'll want to pass a per-origin
## latitude via register_moai's optional `latitude` argument instead.
@export var default_latitude_deg: float = -999.0


# --- State ---
var _beacons: Dictionary = {}        # island_id -> { "pos": Vector3, "latitude": float }
var _pending: Array = []              # [{ origin_id, landing_pos }]
var _routes: Array[Route] = []


# ---------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------

## Register an island as a canonical navigational anchor. Call this
## when the player finishes building a moai on the island. `latitude`
## is the latitude the celestial sphere should use when this island is
## the origin of a route — if omitted, the current celestial sphere
## latitude is captured.
func register_moai(island_id: String, pos: Vector3, latitude: float = INF) -> void:
	var lat: float = latitude
	if not is_finite(lat):
		lat = celestial_sphere.latitude_deg if celestial_sphere else 0.0
	_beacons[island_id] = {"pos": pos, "latitude": lat}
	moai_registered.emit(island_id, pos)
	_resolve_pending_for(island_id, pos)


## Soft-record a landing on an as-yet-uncommitted island. The landing
## point becomes a "pending discovery" that will be resolved into a
## learned route the moment a moai is built near it.
##
## Call this from your gameplay code when the player steps off the
## canoe onto new land. `origin_id` is the island they departed from.
func register_discovery(origin_id: String, landing_pos: Vector3) -> void:
	if not _beacons.has(origin_id):
		push_warning("register_discovery called from unknown origin '%s'" % origin_id)
		return
	_pending.append({"origin_id": origin_id, "landing_pos": landing_pos})
	discovery_recorded.emit(origin_id, landing_pos)


# ---------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------

func get_beacon_position(island_id: String) -> Vector3:
	if _beacons.has(island_id):
		return _beacons[island_id]["pos"]
	return Vector3.ZERO


func has_beacon(island_id: String) -> bool:
	return _beacons.has(island_id)


func learned_route(origin_id: String, destination_id: String) -> Route:
	for r in _routes:
		if r.origin_id == origin_id and r.destination_id == destination_id:
			return r
	return null


func get_routes_from(origin_id: String) -> Array[Route]:
	var out: Array[Route] = []
	for r in _routes:
		if r.origin_id == origin_id:
			out.append(r)
	return out


func get_all_routes() -> Array[Route]:
	return _routes.duplicate()


# ---------------------------------------------------------------------
# Pending discovery resolution
# ---------------------------------------------------------------------

func _resolve_pending_for(new_island_id: String, new_island_pos: Vector3) -> void:
	var remaining: Array = []
	for p in _pending:
		# Can't discover yourself. Shouldn't happen with sane gameplay
		# code but be robust.
		if p.origin_id == new_island_id:
			continue
		var landing: Vector3 = p.landing_pos
		if landing.distance_to(new_island_pos) > moai_discovery_match_radius:
			remaining.append(p)
			continue
		# This discovery belongs to the newly-registered island.
		if not _beacons.has(p.origin_id):
			# Origin was somehow unregistered between discovery and moai.
			# Drop the pending entry — without an origin beacon we can't
			# compute a bearing.
			continue
		var route := _compute_route(p.origin_id, new_island_id)
		if route:
			_routes.append(route)
			route_learned.emit(route)
		# else: no visible star aligned — rare, but possible for due-north
		# or due-south routes on an equatorial latitude. The discovery is
		# consumed regardless; the island is registered, you just don't
		# get a chant.
	_pending = remaining


# ---------------------------------------------------------------------
# Guide-star computation
# ---------------------------------------------------------------------

## Find the star that best aligns with the required bearing from
## origin to destination, across candidate hours of night. The scoring
## prefers stars whose *exact* bow-relative angle lands cleanly on an
## integer house (so the chant reads "house 4" not "house 3.47"),
## breaks ties by brightness, and rejects stars too close to the
## horizon or zenith.
##
## Side effect: temporarily mutates celestial_sphere's time_of_day and
## latitude while scanning. Saved/restored so live gameplay is unaffected.
func _compute_route(origin_id: String, dest_id: String) -> Route:
	if celestial_sphere == null or celestial_sphere.catalog == null:
		return null
	if not _beacons.has(origin_id) or not _beacons.has(dest_id):
		return null

	var origin_pos: Vector3 = _beacons[origin_id]["pos"]
	var dest_pos: Vector3 = _beacons[dest_id]["pos"]
	var origin_lat: float = _beacons[origin_id]["latitude"]

	var delta: Vector3 = dest_pos - origin_pos
	# Flatten to horizontal — altitude differences between moai don't
	# affect the bearing you sail.
	delta.y = 0.0
	var distance: float = delta.length()
	if distance < 0.01:
		return null
	var target_az: float = atan2(delta.x, delta.z)
	var house_width: float = TAU / float(notch_count)

	# Save celestial sphere state.
	var saved_time: float = celestial_sphere.time_of_day_hours
	var saved_lat: float = celestial_sphere.latitude_deg
	celestial_sphere.latitude_deg = origin_lat

	var best_star_id: String = ""
	var best_score: float = INF
	var best_hour: float = 22.0
	var best_house: int = 0

	for hour in candidate_hours:
		celestial_sphere.time_of_day_hours = hour
		for entry in celestial_sphere.catalog.stars:
			if entry == null:
				continue
			var dir: Vector3 = celestial_sphere.get_star_direction(entry.id)
			if dir == Vector3.ZERO:
				continue
			# Require the star to be usefully placed — not grazing the
			# horizon (unreliable in haze) and not near the zenith (no
			# bearing information when a star is straight up).
			if dir.y < 0.15 or dir.y > 0.85:
				continue

			var star_az: float = atan2(dir.x, dir.z)
			var rel: float = fposmod(star_az - target_az, TAU)
			var exact_house: float = rel / house_width
			var rounded: int = int(round(exact_house)) % notch_count
			# "Snap quality": how close did we get to a clean integer
			# house alignment? Zero is perfect.
			var snap_err: float = abs(exact_house - float(rounded))
			if snap_err > 0.5:
				snap_err = 1.0 - snap_err  # handle wraparound

			# Score: lower is better. Brightness is a small bonus so
			# that, all else equal, we pick the more conspicuous star.
			var score: float = snap_err - entry.brightness * 0.02

			if score < best_score:
				best_score = score
				best_star_id = entry.id
				best_hour = hour
				best_house = rounded

	# Restore.
	celestial_sphere.time_of_day_hours = saved_time
	celestial_sphere.latitude_deg = saved_lat

	if best_star_id == "":
		return null

	var route := Route.new()
	route.origin_id = origin_id
	route.destination_id = dest_id
	route.guide_star_id = best_star_id
	route.target_house = best_house
	route.target_hour = best_hour
	route.bearing_rad = target_az
	route.distance_m = distance
	route.chant_text = _default_chant_text(route)
	return route


func _default_chant_text(route: Route) -> String:
	var star_entry: StarEntry = null
	if celestial_sphere and celestial_sphere.catalog:
		star_entry = celestial_sphere.catalog.find_by_id(route.guide_star_id)
	var star_name: String = route.guide_star_id
	if star_entry and star_entry.display_name != "":
		star_name = star_entry.display_name
	var hour_text: String = "%02d:%02d" % [int(route.target_hour), int(fposmod(route.target_hour, 1.0) * 60.0)]
	return "From %s to %s: at %s, hold %s in house %d of the compass." % [
		route.origin_id, route.destination_id, hour_text, star_name, route.target_house
	]


# ---------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------

func to_save_dict() -> Dictionary:
	var routes_data: Array = []
	for r in _routes:
		routes_data.append({
			"origin_id": r.origin_id,
			"destination_id": r.destination_id,
			"guide_star_id": r.guide_star_id,
			"target_house": r.target_house,
			"target_hour": r.target_hour,
			"tolerance_houses": r.tolerance_houses,
			"bearing_rad": r.bearing_rad,
			"distance_m": r.distance_m,
			"chant_text": r.chant_text,
		})
	return {
		"beacons": _beacons.duplicate(true),
		"pending": _pending.duplicate(true),
		"routes": routes_data,
	}


func load_from_save_dict(data: Dictionary) -> void:
	_beacons = data.get("beacons", {}).duplicate(true)
	_pending = data.get("pending", []).duplicate(true)
	_routes.clear()
	for rd in data.get("routes", []):
		var r := Route.new()
		r.origin_id = rd.get("origin_id", "")
		r.destination_id = rd.get("destination_id", "")
		r.guide_star_id = rd.get("guide_star_id", "")
		r.target_house = rd.get("target_house", 0)
		r.target_hour = rd.get("target_hour", 22.0)
		r.tolerance_houses = rd.get("tolerance_houses", 1)
		r.bearing_rad = rd.get("bearing_rad", 0.0)
		r.distance_m = rd.get("distance_m", 0.0)
		r.chant_text = rd.get("chant_text", "")
		_routes.append(r)
