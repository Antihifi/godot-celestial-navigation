# Celestial Navigation for Godot 4 — Sky3D Companion

A named-star overlay and Polynesian-style wayfinding system for [Sky3D](https://github.com/TokisanGames/Sky3D). Renders gameplay-meaningful stars on top of Sky3D's ambient starfield, synchronized with Sky3D's time-of-day, and provides a complete star-compass navigation loop: catalog → focus → inspect → route → steer.

Built for [Kon-Tiki](https://github.com/Antihifi/kontiki), a Polynesian expansion sailing sim. Designed to be reusable in any Godot 4.x project that uses Sky3D.

## What It Does

Sky3D renders stars as pixels in a panoramic texture. You can't highlight them, name them, or interact with them. This addon leaves Sky3D completely untouched and adds a parallel layer of **named stars** as billboard geometry that rotates in sync with Sky3D's sky. From the player's perspective, specific stars in the sky now have names, can be focused, inspected, and used for navigation.

The system includes:

- **Star catalog** — a Resource holding ~15-60 named stars with Polynesian names, celestial coordinates, colors, brightness, lore text, and a learned/unlearned flag for progression
- **Celestial sphere** — a Node3D that renders catalog stars as additive billboards, synced to Sky3D's TimeOfDay rotation and tilted by observer latitude
- **Star focus** — camera-forward dot-product search that finds whichever named star you're looking at and highlights it
- **Star inspector** — click-to-inspect input handler that opens a lore panel
- **Lore panel** — tapa-cloth styled `_draw()` panel showing star info, lore, and any routes using this star
- **Bow compass** — a diegetic 3D carved ring on the canoe prow with 32 houses, sliding N/E/S/W cardinals, and star markers positioned by bow-relative azimuth
- **Compass HUD** — a 2D horizon strip (tutorial/accessibility fallback)
- **Voyage registry** — tracks moai-registered islands, converts landings into learned routes by computing guide stars from bearing geometry
- **Route resource** — a chant stanza: "from A to B, at hour H, hold star S in house N"

## Requirements

- Godot 4.3+ (tested on 4.5)
- [Sky3D](https://github.com/TokisanGames/Sky3D) installed and working

## Install

1. Copy `addons/celestial_nav/` into your project's `addons/` directory
2. Open **Project → Project Settings → Plugins** and enable **Celestial Navigation**
3. Open `addons/celestial_nav/build_example_catalog.gd` in the editor and run it via **File → Run** to generate `polynesian_stars.tres`

## Quick Start

```
YourScene
├ Sky3D                           ← your existing Sky3D setup
├ CelestialSphere (Node3D)        ← attach celestial_sphere.gd
│   catalog = polynesian_stars.tres
│   sky3d_time_source = Sky3D/TimeOfDay
├ VoyageRegistry (Node)           ← attach voyage_registry.gd
│   celestial_sphere = CelestialSphere
├ Camera3D
│ ├ StarFocus (Node)              ← attach star_focus.gd
│ └ StarInspector (Node)          ← attach star_inspector.gd
├ PlayerCanoe (Node3D)
│ └ BowCompass (Node3D)           ← attach bow_compass.gd, position on prow
└ CanvasLayer
  ├ StarCompassHUD (Control)      ← attach star_compass_hud.gd
  └ StarLorePanel (Control)       ← attach star_lore_panel.gd
```

Wire up the `@export` references in the inspector. Parent `CelestialSphere` under your Camera3D if you want stars to track the player (recommended).

## How the Navigation Loop Works

Stars don't point to islands. Stars point to **routes between islands**.

1. **Register origin** — player builds a moai on their home island. `VoyageRegistry.register_moai("tahiti", moai_position)` captures the island's world position and latitude.
2. **Discover** — player sails out, lands on new shore. `VoyageRegistry.register_discovery("tahiti", landing_position)` records a pending discovery.
3. **Commit** — player builds a moai on the new island. `VoyageRegistry.register_moai("hawaii", moai_position)` resolves the pending discovery into a learned **Route**: the registry scans the star catalog to find which star best aligns with the bearing from origin to destination at a plausible hour of night.
4. **Navigate** — player consults the chant log: "From Tahiti to Hawai'i: at 22:00, hold Hōkūle'a in house 4." They wait for the right hour, steer the canoe until `bow_compass.get_star_house("arcturus") == 4`, and hold course.

## Key API

```gdscript
# Steering check (every frame while sailing a route):
var route := registry.learned_route("tahiti", "hawaii")
var house := bow_compass.get_star_house(route.guide_star_id)
if route.is_on_course(house, bow_compass.notch_count):
    # on course

# Angular error for smooth feedback:
var err := bow_compass.get_star_house_error(route.guide_star_id, route.target_house)
# err approaches 0.0 as alignment improves

# Star queries:
var az := celestial_sphere.get_star_azimuth("arcturus")  # radians, or INF if below horizon
var visible := celestial_sphere.is_star_visible("arcturus")
var dir := celestial_sphere.get_star_direction("arcturus")  # unit Vector3

# Progression:
celestial_sphere.catalog.set_learned("arcturus", true)
```

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `star_entry.gd` | 50 | Single-star Resource |
| `star_catalog.gd` | 20 | Array of StarEntry resources |
| `celestial_sphere.gd` | 285 | Sky3D-synced star renderer |
| `star_billboard.gdshader` | 70 | Procedural additive star sprite |
| `star_focus.gd` | 85 | Camera-forward star detection |
| `star_inspector.gd` | 120 | Click-to-inspect input handler |
| `star_lore_panel.gd` | 450 | Tapa-cloth styled info panel |
| `bow_compass.gd` | 410 | 3D diegetic 32-house compass |
| `star_compass_hud.gd` | 270 | 2D horizon strip HUD |
| `route.gd` | 70 | Learned navigational chant |
| `voyage_registry.gd` | 310 | Island registration + route computation |
| `build_example_catalog.gd` | 120 | Generates example .tres catalog |
| `plugin.cfg` | 8 | Godot plugin descriptor |

## Sky3D Sync

CelestialSphere reads a float property from Sky3D's TimeOfDay node each frame (`total_hours` by default). It computes its own rotation matrix from that value and applies it to all star positions. The stars rise in the east, cross the sky, and set in the west in lockstep with Sky3D's background starmap. The two layers are independent — this addon never modifies Sky3D's shader, nodes, or state.

If your stars aren't rotating with the sky, check that `sky3d_time_property` matches the actual property name on your TimeOfDay node. Print `your_time_node.get_property_list()` to find it.

## Design Philosophy

- **Gameplay-first astronomy.** Clean 24h rotation, no sidereal drift, no precession, no planets. Stars are learnable and authorable, not astronomically correct.
- **No textures required.** Stars are procedural shader billboards. The lore panel and compass HUD are pure `_draw()`. The bow compass uses primitive meshes. Ship no art to get started.
- **Sky3D is untouched.** Zero modifications to Sky3D's scripts, shaders, or scene. The addon is purely additive.
- **Routes, not waypoints.** Guide stars are (origin, destination) pairs computed from world-space bearing geometry. Different origin → different star for the same destination. This is how real Polynesian wayfinding works.

## Cultural Note

This system is inspired by real Polynesian wayfinding techniques, particularly the Hawaiian star compass tradition taught by Mau Piailug and practiced aboard Hōkūleʻa. Polynesian cultures are living cultures. If you ship a game using this system, consider consulting with navigators or cultural practitioners from the relevant communities. The [Polynesian Voyaging Society](https://www.hokulea.com/) is a good starting point.

## License

MIT. See [LICENSE](LICENSE).
