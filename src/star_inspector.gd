class_name StarInspector
extends Node

## Bridges StarFocus (which star am I looking at?) with StarLorePanel
## (show me that star's information). Listens for an input action while
## a star is focused and opens / closes the panel.
##
## Setup:
##   1. Add as a child of your Camera3D alongside StarFocus.
##   2. Assign `star_focus` and `lore_panel` in the inspector.
##   3. Create an input action called "inspect_star" (default) bound to
##      whatever you like — left click, a gamepad face button, etc.
##      Or change `inspect_action` to match an existing action.
##
## The panel auto-closes when the player looks away (focus lost) unless
## `pin_on_open` is true, in which case it stays until the player
## explicitly closes it or opens a different star.

@export var star_focus: StarFocus
@export var lore_panel: Control  # StarLorePanel instance

## Name of the InputMap action that opens the lore panel.
@export var inspect_action: StringName = &"inspect_star"

## If true, the panel stays open even when focus is lost. The player
## must press the action again or focus a different star to close it.
## Good for gamepad where holding a steady gaze is harder.
@export var pin_on_open: bool = false

## If true, pressing the action while the panel is already open for the
## same star closes it (toggle behavior).
@export var toggle: bool = true

## Optional: the VoyageRegistry, so the lore panel can show routes
## involving this star.
@export var voyage_registry: Node  # VoyageRegistry

var _inspected_id: String = ""
var _action_exists: bool = false


func _ready() -> void:
	_action_exists = InputMap.has_action(inspect_action)
	if not _action_exists:
		# Auto-create a default binding so the system works out of the
		# box even if the developer hasn't touched InputMap yet.
		# Left mouse button as default — swap for gamepad as needed.
		InputMap.add_action(inspect_action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(inspect_action, ev)
		_action_exists = true

	if star_focus:
		star_focus.focus_changed.connect(_on_focus_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _action_exists:
		return
	if not event.is_action_pressed(inspect_action):
		return
	if star_focus == null or lore_panel == null:
		return

	var focused_id: String = star_focus.get_focused_id()
	if focused_id == "":
		# Clicked with nothing focused — close if open.
		_close_panel()
		return

	if focused_id == _inspected_id and toggle:
		# Same star, toggle off.
		_close_panel()
		return

	# Open (or switch to) the focused star.
	_open_panel(focused_id)


func _on_focus_changed(new_id: String) -> void:
	if _inspected_id == "":
		return  # Panel not open, nothing to do.
	if new_id == "":
		# Focus lost.
		if not pin_on_open:
			_close_panel()
	elif new_id != _inspected_id:
		# Focus shifted to a different star while panel is open — follow it.
		_open_panel(new_id)


func _open_panel(star_id: String) -> void:
	_inspected_id = star_id
	if lore_panel == null:
		return
	var entry: StarEntry = null
	if star_focus and star_focus.celestial_sphere and star_focus.celestial_sphere.catalog:
		entry = star_focus.celestial_sphere.catalog.find_by_id(star_id)

	# Gather routes involving this star, if registry is connected.
	var routes: Array = []
	if voyage_registry and voyage_registry.has_method("get_all_routes"):
		for r in voyage_registry.get_all_routes():
			if r.guide_star_id == star_id:
				routes.append(r)

	if lore_panel.has_method("show_star"):
		lore_panel.show_star(entry, routes)
	else:
		lore_panel.visible = true


func _close_panel() -> void:
	_inspected_id = ""
	if lore_panel == null:
		return
	if lore_panel.has_method("hide_star"):
		lore_panel.hide_star()
	else:
		lore_panel.visible = false
