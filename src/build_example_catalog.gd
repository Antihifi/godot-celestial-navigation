@tool
extends EditorScript

## Run this from the editor (File > Run) to generate an example
## `polynesian_stars.tres` catalog next to this script, seeded with real
## wayfinding stars used by Polynesian navigators.
##
## The declinations here are approximately real; right ascensions are
## approximate too but have been nudged so they spread out nicely across
## the night as a first playable pass. Tune freely — for gameplay, what
## matters is that they're *consistent* and *learnable*, not astronomically
## perfect. Real wayfinders memorized rising points, not RA/Dec.

const StarCatalogScript = preload("res://addons/celestial_nav/star_catalog.gd")
const StarEntryScript = preload("res://addons/celestial_nav/star_entry.gd")


func _run() -> void:
	var catalog: StarCatalog = StarCatalogScript.new()

	catalog.stars = [
		_make(
			"arcturus", "Hōkūle'a",
			19.2, 213.9, 2.8, Color(1.0, 0.85, 0.55),
			true,
			"The zenith star of Hawai'i. When it passes directly overhead "
			+ "at night, you are at the latitude of the islands."
		),
		_make(
			"sirius", "'A'ā",
			-16.7, 101.3, 3.2, Color(0.85, 0.92, 1.0),
			true,
			"The brightest star in the sky. Burns fiercely above the "
			+ "southeastern horizon in winter."
		),
		_make(
			"canopus", "Ke Ali'i o Kona i ka Lewa",
			-52.7, 95.9, 2.6, Color(1.0, 0.98, 0.9),
			false,
			"Chief of the Southern Expanse. A southern beacon seen from "
			+ "the deep Pacific."
		),
		_make(
			"spica", "Hikianalia",
			-11.2, 201.3, 1.8, Color(0.9, 0.95, 1.0),
			false,
			"Companion to Hōkūle'a. The two rise together and guide "
			+ "travelers between the northern and southern skies."
		),
		_make(
			"altair", "Humu",
			8.9, 297.7, 1.7, Color(1.0, 1.0, 0.95),
			false,
			"The zenith star of the Society Islands."
		),
		_make(
			"vega", "Keoe",
			38.8, 279.2, 1.9, Color(0.9, 0.95, 1.0),
			false,
			"A northern beacon. Marks the path back toward Hawai'i in summer."
		),
		_make(
			"antares", "Lehua Kona",
			-26.4, 247.4, 1.6, Color(1.0, 0.65, 0.5),
			false,
			"The red heart of the scorpion. Rises in the southeast on "
			+ "long summer nights."
		),
		_make(
			"acrux", "Hānaiakamalama",
			-63.1, 186.6, 1.5, Color(0.95, 0.95, 1.0),
			false,
			"Brightest of the Southern Cross. Never rises above the "
			+ "horizon north of about twenty-five degrees latitude — if "
			+ "you can still see it, you are south of Hawai'i."
		),
		_make(
			"polaris", "Hōkū Pa'a",
			89.3, 37.9, 1.2, Color(1.0, 0.98, 0.9),
			false,
			"The Fixed Star. Sits at the celestial pole; its altitude "
			+ "above the horizon equals your latitude north of the equator."
		),
		_make(
			"rigel", "Puana",
			-8.2, 78.6, 1.6, Color(0.8, 0.9, 1.0),
			false,
			"Blue-white blossom at the foot of the hunter."
		),
		_make(
			"betelgeuse", "Kaulua",
			7.4, 88.8, 1.5, Color(1.0, 0.6, 0.45),
			false,
			"The red shoulder. Its fading and brightening are watched "
			+ "by those who keep the chants."
		),
		_make(
			"aldebaran", "Kapuahi",
			16.5, 68.9, 1.4, Color(1.0, 0.75, 0.55),
			false,
			"The fire of the sacred oven. Rises before the Pleiades."
		),
		_make(
			"pleiades", "Makali'i",
			24.1, 56.75, 2.0, Color(0.85, 0.92, 1.0),
			true,
			"The Little Eyes. When Makali'i rises at sunset, the new "
			+ "year begins and the season of voyaging opens."
		),
		_make(
			"achernar", "Ke Ka o Makali'i",
			-57.2, 24.4, 1.4, Color(0.85, 0.92, 1.0),
			false,
			"A southern light. Rises and sets close to the southern horizon."
		),
		_make(
			"fomalhaut", "Keoe-loa",
			-29.6, 344.4, 1.3, Color(1.0, 0.98, 0.9),
			false,
			"The solitary mouth. Burns alone in an otherwise dim stretch "
			+ "of sky."
		),
	]

	var out_path: String = (get_script() as Script).resource_path.get_base_dir() \
		+ "/polynesian_stars.tres"
	var err := ResourceSaver.save(catalog, out_path)
	if err == OK:
		print("Wrote ", catalog.stars.size(), " stars to ", out_path)
	else:
		push_error("Failed to save catalog: %s" % err)


func _make(
	id: String,
	display_name: String,
	dec: float,
	ra: float,
	brightness: float,
	color: Color,
	learned: bool,
	lore: String
) -> StarEntry:
	var e: StarEntry = StarEntryScript.new()
	e.id = id
	e.display_name = display_name
	e.declination_deg = dec
	e.right_ascension_deg = ra
	e.brightness = brightness
	e.color = color
	e.learned = learned
	e.lore = lore
	return e
