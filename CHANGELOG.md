# Changelog

Per-fix log of changes shipped after the initial commit. Each entry
captures the symptom, root cause, and resolution so future contributors
can understand the *why* behind each piece of API.

---

## 0. Do NOT set owner on @tool-created billboards (fixed — editor UX)

**File:** `celestial_sphere.gd`, `_rebuild_if_needed()`

**Symptom:** Opening a scene that contains a CelestialSphere floods the editor
with hundreds of `ERROR: Node not found: ".../GameWorld/ThirdPersonCamera/CelestialSphere/@MeshInstance3D@N"` errors from the Scene Tree dock.

**Root cause:** `@tool` script creates MeshInstance3D billboards at `_ready`
and sets `mi.owner = get_tree().edited_scene_root` in editor mode. This
serializes the billboards into the .tscn file. On next scene open, the script's
own startup-cleanup logic queue_frees them (they get re-created from the
catalog), but the Scene Tree dock retains paths to the old nodes and floods
stderr trying to resolve them.

**Fix:** Don't set `mi.owner` in the editor — billboards are transient preview
meshes. They should NOT persist in the scene file. Simply:

```gdscript
add_child(mi)
# no owner assignment — preview-only
```

Billboards still render correctly in the editor (tool script's `_process`
keeps updating them). They just aren't serialized, so no stale-path errors.

---

## 1. Camera far-plane clamp (fixed)

**File:** `celestial_sphere.gd`, `_ready()`

**Symptom:** Stars invisible at runtime. Default `radius = 5000` is beyond
Godot's default Camera3D `far = 4000`, so billboards get depth-clipped.

**Fix:** Auto-clamp radius at startup to 85% of active camera's far plane:
```gdscript
var cam: Camera3D = get_viewport().get_camera_3d()
if cam:
    radius = minf(radius, cam.far * 0.85)
```

Alternatively, change default `radius` from `5000.0` to `3500.0`.

---

## 2. Stale @tool billboard cleanup (fixed)

**File:** `celestial_sphere.gd`, `_rebuild_if_needed()`

**Symptom:** When the scene is saved while @tool is active, billboard
`MeshInstance3D` children are serialized into the .tscn. At runtime, the
tracked `_star_nodes` array is empty, so these stale editor-saved children
aren't cleaned up. They pile up on every save and stay as dead weight with
`visible = false`.

**Fix:** At rebuild time, also remove any pre-existing `MeshInstance3D`
children (not just tracked ones):
```gdscript
for child in get_children():
    if child is MeshInstance3D:
        child.queue_free()
```

---

## 3. Stars follow camera rotation (not yet fixed — in progress)

**File:** `celestial_sphere.gd`, `_update_star_transforms()`

**Symptom:** When CelestialSphere is parented to the player's Camera3D (as
INTEGRATION.md recommends), billboards inherit the camera's rotation. Since
`mi.position = dir * radius` is local, stars rotate with the camera view
instead of staying fixed in the world's sky.

**Root cause:** Local position × parent (camera) rotation = stars drift with
camera yaw/pitch. They should be in world space.

**Fix:** Set `top_level = true` on each billboard MeshInstance3D so it
ignores the parent transform, then set `global_position` computed from the
CelestialSphere's world position + `dir * radius`:
```gdscript
# In _rebuild_if_needed, when creating mi:
mi.top_level = true

# In _update_star_transforms, replace:
# mi.position = dir * radius
# with:
mi.global_position = global_position + dir * radius
```

This keeps stars fixed in world space while still following the camera's
position (so they remain at infinite-feeling distance as the player moves).

---

## 4. Star visibility through post-processing (partially fixed)

**File:** `star_billboard.gdshader`, `celestial_sphere.gd`

**Symptom:** Projects with aggressive post-processing (cel-banding,
posterize, etc.) can crush the soft additive star halos into the background
quantization bands. Stars render but are invisible after composite.

**Fix:** Add a `min_core_intensity` uniform (default 1.5) to the shader so
the core always renders as a solid bright dot regardless of per-star
brightness, plus raise `glow_strength` default from 0.35 → 0.8. Also expose
`base_star_size` tuning — default 60 is too small for heavily
post-processed pipelines; suggest raising default or documenting the
tuning need in INTEGRATION.md.

---

## 5. Default `sky3d_time_property` value (documentation)

**File:** `celestial_sphere.gd`

**Symptom:** Default value is `&"total_hours"` but Sky3D's `TimeOfDay`
actually exposes `current_time` (range 0.0..23.9998). INTEGRATION.md
already notes this, but the script default is misleading.

**Fix:** Change default value to `&"current_time"` to match the current
Sky3D addon API, or document both conventions in the script header.

---

## 7b. StarFocus tolerance tuning (fixed via retune of existing knobs)

**File:** `star_focus.gd`

**Symptom:** Default `focus_angle_deg=4.0` is tight — any small camera wobble
while hovering on a star loses focus. Default `focus_grace_seconds=0.35`
expires quickly. Players clicking on a visibly-pulsing star often get
`focused_id=''` in logs because focus flickered off between reticle alignment
and click.

**Fix:** Bump defaults — `focus_angle_deg: 4.0 → 7.0` (gives reticle aim
a forgiving cone) and `focus_grace_seconds: 0.35 → 1.5` + raise its
@export_range max from 1.0 → 3.0. Both are still player-tunable via
inspector; defaults now feel reliable.

---

## 7. StarFocus grace period (fixed)

**File:** `star_focus.gd`

**Symptom:** Small mouse-wobble at the moment of click drops focus below
the 4° angular threshold. The click event fires with `_focused_id == ""`,
so `StarInspector` opens the lore panel with no target and immediately
closes. User experience: clicking "on" a star does nothing.

**Fix:** Add `@export var focus_grace_seconds: float = 0.35`. Track
`_last_focused_id` and `_time_since_focus_lost`. `get_focused_id()` returns
the last-focused star during the grace window:

```gdscript
func get_focused_id() -> String:
    if _focused_id != "":
        return _focused_id
    if _time_since_focus_lost < focus_grace_seconds and _last_focused_id != "":
        return _last_focused_id
    return ""
```

Also bumped `get_focused_entry()` to use this same method.

---

## 8. Highlighted stars punch through cel post-process (fixed)

**File:** `celestial_sphere.gd`

**Symptom:** `highlight()` sets a pulsing brightness boost, but downstream
cel / posterize shaders crush the boost into the same luminance band as
unfocused stars. Players can't see which star they're aimed at.

**Fix:** In `_update_star_transforms`, when a star is highlighted, set the
shader's `min_core_intensity` to a higher floor (3.5 * pulse). Non-highlighted
stars use 1.5 (default). Ensures the focused core always renders brighter
than neighbours regardless of post-processing quantization.

```gdscript
if is_highlighted:
    mat.set_shader_parameter(&"min_core_intensity", 3.5 * pulse)
else:
    mat.set_shader_parameter(&"min_core_intensity", 1.5)
```

---

## 6. BowCompass anchor node (fixed)

**File:** `bow_compass.gd`

**Symptom:** BowCompass renders at its own node transform, which forces
integrators to place it exactly where they want the ring to appear. On
complex vessel scenes (sailing_canoe.tscn with dozens of rigging nodes),
dropping BowCompass at the right world position is fiddly and the ring
often ends up at the boat's origin (under the hull).

**Fix:** Add an optional `@export var anchor: Node3D` property. If assigned,
each frame `global_transform = anchor.global_transform`. Users drop a
Marker3D anywhere they want the compass (mast top, bow crossbeam, above
deck) and assign it to the anchor export — BowCompass snaps to it.

```gdscript
@export var anchor: Node3D

func _process(_delta: float) -> void:
    ...
    if anchor and is_instance_valid(anchor):
        global_transform = anchor.global_transform
    ...
```

---

## 9. BowCompass: replace N/E/S/W cardinals with traditional 32-house names + target-house API (fixed)

**File:** `bow_compass.gd`

**Symptom:** The compass ring rendered sliding `N`, `E`, `S`, `W` letters — a Western navigational abstraction that defeats the whole point of a Polynesian wayfinding game. If the player always knows which direction is north, star-based navigation is decorative rather than load-bearing.

**Fix:** Remove the 4 sliding cardinal labels entirely. Replace with:

1. A constant `HAWAIIAN_HOUSES: PackedStringArray` of 32 traditional star-house names (Haka Koʻolau, Nā Leo Koʻolau, … Hikina, … Hema, … Komohana, Haka Hoʻolua). Houses are world-oriented (fixed to horizon), indexed clockwise starting at true north.

2. A single **bow-house label** fixed at the bow notch (rel = 0) that updates every frame to show the name of whichever house the bow currently points at. Players read "bow on *Nā Leo Koʻolau*" rather than "bow on E by NE" — diegetic, authentic, and useful for correcting course against a learned chant.

3. Public API for external integrations (e.g. active-route steering):
   ```gdscript
   func set_target_house(house: int) -> void   # highlights that notch in target_notch_color
   func clear_target_house() -> void
   @export var target_notch_color: Color = Color(0.4, 1.0, 0.55)
   ```

   Callers (e.g. a RouteSteering controller) pass the target house of an active Route; the ring lights one notch so the player can visually aim the guide star at it. Works even when not helming — gives the ring navigational meaning at a glance.

4. Internal refactor: `_build_notches` now caches `_notch_materials: Array[StandardMaterial3D]` and `_notch_base_colors: Array[Color]` so `set_target_house` can restore the previous highlighted notch to its correct major/minor color + emission energy.

The `cardinal_color` / `cardinal_font_size` exports are retained as styling knobs for the bow-house label — existing inspector tuning carries over.

### Why this belongs upstream

Every Polynesian / wayfinding-flavored game using this addon will want the star-house naming, not the Western cardinals. The 32 Hawaiian names are the canonical Nainoa Thompson / PVS compass. Projects that want different naming (Tahitian, Māori, Carolinian) can replace `HAWAIIAN_HOUSES` with their own `house_names` `@export` array — easy follow-up once the refactor is in.

---

## 10. BowCompass: bow-axis convention knob applied as a basis rotation (fixed)

**File:** `bow_compass.gd`

**Symptom:** Many imported boat models (Blender exports, asset-store canoes) have their bow pointing along local **+Z** instead of Godot's standard **-Z** — and frequently their port axis sits at +X where Godot would expect starboard. With the addon's previous assumption (`-_canoe.global_transform.basis.z == forward`):

- The bow-house label appeared at the **stern** end of the ring.
- `get_star_house()` returned house indices counted from the stern.
- Star markers landed on the **mirrored** side of the ring (a star to starboard rendered to port), and the ring rotated *backwards* as the canoe yawed.

The first two are 180° rotation bugs; the third is a +X/-X mirror. **Any single yaw-scalar offset only fixes the first two — the mirror persists** because the local +X axis is still pointing the wrong way.

**Fix:** `@export_range(-PI, PI, 0.01) var bow_yaw_offset: float = 0.0` is now applied as a real **rotation of the compass node's basis** each frame (or once at `_ready` if no anchor is assigned), not as a scalar added to a derived yaw value. Rotating the basis around Y simultaneously corrects the forward axis AND the starboard axis, because rotating a frame 180° flips both -Z↔+Z and +X↔-X. After the rotation the compass's own local frame is Godot-standard regardless of how the canoe model was authored.

Because the compass's basis is now correct in world, downstream math reads it directly:

```gdscript
func get_canoe_world_yaw() -> float:
    var fwd: Vector3 = -global_transform.basis.z
    return atan2(fwd.x, fwd.z)
```

Promoted to public API (`get_*` not `_*`) so external steering / feedback nodes can read the canoe's hull-relative bearing without re-deriving it. All three former call-sites (the two public `get_star_house*` methods plus the per-frame `_process` ring update) funnel through the helper.

For canoes whose bow points at +Z (or whose hull frame is otherwise rotated 180° from Godot convention), set `bow_yaw_offset = PI` in the inspector — done. The same knob fixes both the rotation AND the mirror in one move.

---

## 11. RouteSteering / docs: enabling progression-gated below-horizon hints (Kon-Tiki side, not addon)

**Context (not a bug, just a design note for downstream integrators):** A natural addon API question is "should the addon emit a below-horizon hint string for free?" The Kon-Tiki integration deliberately *doesn't* — direction hints are gameplay, gated behind a future Minor-Moai unlock so the player has to earn a deeper read on the sky. Without it, the message is the bare "Guide star is below the horizon."

The new `BowCompass.get_canoe_world_yaw()` (item 10) plus the long-standing `CelestialSphere.get_star_direction()` (which returns a valid direction even when below horizon) are sufficient for any integrator to build their own gated hint:

```gdscript
func _below_horizon_hint(star_id: String) -> String:
    var dir: Vector3 = celestial_sphere.get_star_direction(star_id)
    var canoe_yaw: float = bow_compass.get_canoe_world_yaw()
    var rel: float = fposmod(atan2(dir.x, dir.z) - canoe_yaw + PI, TAU) - PI
    # → "ahead" / "astern" / "off your port" / "off your starboard"
```

Recording it in this doc rather than in the addon means the addon stays minimal while still being able to support hint UIs.

A useful future addon helper would be `CelestialSphere.estimate_star_rise_hour(star_id)` for "rises in ~2 hours" — leaving as a TODO.

---

## TODO — Additional tuning / docs

- Document the `top_level = true` design in the addon README since it's a
  non-obvious fix for any parent-to-camera setup.
- Consider adding a "High-contrast mode" toggle on CelestialSphere that
  enables the min_core_intensity shader behavior for stylized pipelines.
