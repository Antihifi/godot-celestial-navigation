@tool
class_name StarEntry
extends Resource

## A single navigationally meaningful star.
##
## Stored in celestial coordinates (declination + right ascension) so you can
## author stars the way real sky catalogs describe them. The CelestialSphere
## converts these to world-space directions each frame, rotated by time-of-day
## and tilted by the observer's latitude.

## English / scientific name (e.g. "Arcturus"). Used as unique id.
@export var id: String = ""

## Name shown to the player. Lean into the Polynesian naming here.
@export var display_name: String = ""

## Declination in degrees (-90 = south celestial pole, +90 = north).
## For equatorial-Pacific gameplay, values roughly in the -60..+60 range
## are where interesting wayfinding stars live.
@export_range(-90.0, 90.0, 0.01) var declination_deg: float = 0.0

## Right ascension in degrees (0..360). Controls *when* in the night the star
## rises. Two stars with the same declination but different RA rise at
## different times — that's what makes the sky a clock.
@export_range(0.0, 360.0, 0.01) var right_ascension_deg: float = 0.0

## Relative brightness. 1.0 = ordinary star, 2.0+ = conspicuous, 3.0+ = beacon.
## This is intentionally *not* astronomical magnitude; it's a gameplay knob.
@export_range(0.1, 5.0, 0.05) var brightness: float = 1.0

## Base color. Most stars should be near-white; tint slightly for variety
## (Betelgeuse-red, Rigel-blue, etc.) or to mark culturally significant stars.
@export var color: Color = Color(1.0, 0.98, 0.92)

## Has the player "learned" this star yet? Unlearned stars still render
## faintly (so the sky isn't empty) but don't show labels or count for
## navigation checks. Flip this from your progression system.
@export var learned: bool = false

## Free-form notes — chant stanza, which island it points to, lore, etc.
## Not used by the renderer; read it from your UI / quest code.
@export_multiline var lore: String = ""


## Returns the star's fixed direction on the celestial sphere, in a frame
## where +Y is the north celestial pole. The CelestialSphere rotates this
## into world space based on time-of-day and latitude.
func get_celestial_direction() -> Vector3:
	var dec := deg_to_rad(declination_deg)
	var ra := deg_to_rad(right_ascension_deg)
	return Vector3(
		cos(dec) * sin(ra),
		sin(dec),
		cos(dec) * cos(ra)
	)
