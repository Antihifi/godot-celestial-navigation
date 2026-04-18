class_name Route
extends Resource

## A learned navigational chant: "from A to B, at hour H, hold star S
## in house N of the bow compass."
##
## Routes are produced by VoyageRegistry when a player completes a
## discovery loop (land → build moai). They're the persistent entry in
## the player's chant log and the source of truth for the steering
## feedback loop.

## Canonical island ids as used by VoyageRegistry.
@export var origin_id: String = ""
@export var destination_id: String = ""

## The star the player holds to fly this route.
@export var guide_star_id: String = ""

## Which bow-compass house the star should sit in when the canoe is
## correctly aligned. Range: [0, VoyageRegistry.notch_count).
@export var target_house: int = 0

## Hour of night (0..24) at which the chant applies. Stars sweep the
## sky over the course of the night, so a route cued to 22:00 will be
## wrong at 02:00 — the star has moved. The chant log UI should show
## this prominently.
@export_range(0.0, 24.0, 0.25) var target_hour: float = 22.0

## Forgiveness, in number of houses. A route with tolerance 1 counts
## as "on course" when the star is within ±1 house of target. Tighter
## tolerance = harder to steer, more dramatic when you drift.
@export var tolerance_houses: int = 1

## The world bearing (radians, 0 = +Z / north) the route follows.
## Cached at registration time; used for redundancy checks and to fall
## back on raw heading if the sky is overcast.
@export var bearing_rad: float = 0.0

## Great-circle-ish distance cached at registration time (meters).
@export var distance_m: float = 0.0

## Human-readable chant stanza shown in the log. Auto-populated at
## registration but editable — you can replace with hand-written text
## or localized strings once your content pipeline is running.
@export_multiline var chant_text: String = ""


## Returns true if the current bow-compass reading (via
## `bow_compass.get_star_house(guide_star_id)`) is within tolerance
## of target_house. Handles wraparound correctly.
func is_on_course(current_house: int, notch_count: int) -> bool:
	if current_house < 0:
		return false  # star not visible
	var diff: int = _wrap_house_diff(current_house - target_house, notch_count)
	return abs(diff) <= tolerance_houses


## Returns signed house error, in [-notch_count/2, notch_count/2].
## Negative = player must turn toward port, positive = toward starboard.
func house_error(current_house: int, notch_count: int) -> int:
	if current_house < 0:
		return 0
	return _wrap_house_diff(current_house - target_house, notch_count)


static func _wrap_house_diff(d: int, notch_count: int) -> int:
	var half: int = notch_count / 2
	d = ((d + half) % notch_count + notch_count) % notch_count - half
	return d
