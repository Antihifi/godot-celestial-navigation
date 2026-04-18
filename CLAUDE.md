# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type

This repo is a **Godot 4 editor plugin** (GDScript). There is no build system, package manager, or test runner — all code runs inside the Godot 4.3+ editor/runtime. The repo layout (source under [src/](src/)) maps to a consumer project's `addons/celestial_nav/` directory at install time. Paths inside scripts (e.g. `load("res://addons/celestial_nav/star_billboard.gdshader")`) assume that installed location; each script also falls back to its own `resource_path.get_base_dir()` so the files work regardless of where the user dropped them.

The companion dependency is [Sky3D](https://github.com/TokisanGames/Sky3D). This addon never modifies Sky3D — it reads one float property (`total_hours` by default) from a `TimeOfDay` node and otherwise runs as a parallel additive layer.

## Common Workflow

- **Iterate**: edit `.gd` files, reopen the consumer scene in Godot, press play. No compile step.
- **Generate the example catalog**: in the editor, open [src/build_example_catalog.gd](src/build_example_catalog.gd) and run **File → Run**. It writes `polynesian_stars.tres` next to itself. This file is `.gitignore`'d on purpose — users regenerate it.
- **Debugging sync issues**: if stars don't rotate with Sky3D, the `sky3d_time_property` name on `CelestialSphere` doesn't match the TimeOfDay node's actual property. Call `get_property_list()` on that node to find the right name.
- **Debugging "compass is rotated 180°"**: see the `-cos` on Z in [src/bow_compass.gd:402](src/bow_compass.gd#L402) — Godot's forward axis is local `-Z`, so `rel=0` (bow) must map to `(0, lift, -ring_radius)`.

## Architecture

The system is organized around one central node (`CelestialSphere`) that every other component reads from. Data flows in one direction — nothing writes back to the sphere except `highlight()` toggles.

```
Sky3D.TimeOfDay.total_hours
          │ (read-only poll each frame)
          ▼
    CelestialSphere ◄─── StarCatalog (Resource; Array[StarEntry])
       │     │ ▲
       │     │ └──── StarFocus (dot-product search on camera.forward)
       │     │              │ emits focus_changed
       │     ▼              ▼
       │   BowCompass ◄── StarInspector → StarLorePanel
       │   StarCompassHUD
       │
       └──► VoyageRegistry ──► Route (Resource)
                │
           register_moai / register_discovery
```

### Coordinate conventions (non-obvious)

- Stars are authored in **celestial coordinates** (`declination_deg`, `right_ascension_deg`) on `StarEntry`. `get_celestial_direction()` converts to a fixed-frame unit vector where `+Y` = north celestial pole.
- `CelestialSphere._celestial_basis()` rotates that frame into world space: a daily rotation around `+Y` by `-(hours/24) * TAU` (negative so stars rise in `+X`/east), then a tilt around `+X` by `(latitude - 90°)` so the pole lands at the correct altitude. Azimuths are `atan2(dir.x, dir.z)`, `0 = +Z = north`, increasing clockwise — the same convention used throughout the codebase.
- **`BowCompass` houses are hull-relative**, not world-relative: `get_star_house()` subtracts `canoe_yaw` before bucketing. House 0 is dead ahead, house `notch_count/4` is starboard beam. This is what makes the compass a steering instrument rather than a readout. `VoyageRegistry` must use the **same** `notch_count` as `BowCompass`.
- Horizon culling uses `dir.y` (which is `sin(altitude)`) directly, not an angle. `horizon_cutoff` should match across `CelestialSphere`, `BowCompass`, and any HUD for visual consistency.

### The routes-not-waypoints model

`VoyageRegistry` is where the gameplay loop lives and is the least obvious part of the design. Stars do not point to islands; **stars point to (origin, destination) route pairs**. A `Route` is computed once, when the player places a second moai that resolves a pending discovery:

1. `_compute_route()` scans every star at every `candidate_hour` while temporarily overwriting `celestial_sphere.time_of_day_hours` and `latitude_deg` (state is saved/restored — don't call this mid-frame from code that reads the sphere).
2. Stars grazing the horizon (`dir.y < 0.15`) or near the zenith (`dir.y > 0.85`) are rejected — the former are unreliable, the latter give no bearing information.
3. Scoring is `snap_err - brightness * 0.02`: lower is better. `snap_err` measures how cleanly the star's bow-relative angle lands on an integer house, so chants read "house 4" rather than "house 3.47". Brightness is a small tiebreaker.
4. Steering feedback each frame is `route.is_on_course(bow_compass.get_star_house(route.guide_star_id), bow_compass.notch_count)`.

### Persistence

`VoyageRegistry.to_save_dict()` / `load_from_save_dict()` serialize the full registry state (`_beacons`, `_pending`, `_routes`). The `StarCatalog` itself is authored content, not save state — `learned` flags on individual `StarEntry` resources persist through whatever mechanism saves the `.tres`.

### `@tool` scripts

`CelestialSphere`, `StarEntry`, and `StarCatalog` are `@tool` so the catalog is editable and the sphere previews in-editor. When modifying these, guard editor-only logic with `Engine.is_editor_hint()` (see `_rebuild_if_needed()` setting `mi.owner = get_tree().edited_scene_root`). `BowCompass`, `StarFocus`, and `VoyageRegistry` are intentionally **not** `@tool` — they depend on a running canoe / camera / gameplay state.

## Design Invariants

These are load-bearing and shouldn't be changed casually:

- **Sky3D is read-only.** No script here writes to Sky3D nodes, modifies its shaders, or depends on its internal state beyond a single float property.
- **No required textures.** Stars are a procedural shader ([src/star_billboard.gdshader](src/star_billboard.gdshader), additive, unshaded). Lore panel and HUD compass are pure `_draw()`. Bow compass uses primitive meshes + `Label3D`. Adding a texture dependency is a regression.
- **`StarEntry.id` is the primary key everywhere.** Never index catalogs by display name or array position; always `catalog.find_by_id(id)`. `display_name` is player-facing and can be any language/script.
- **Gameplay astronomy, not real astronomy.** No sidereal drift, no precession, no planets, 24-hour clean rotation. Don't "fix" this toward realism without an explicit ask.
