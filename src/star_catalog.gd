@tool
class_name StarCatalog
extends Resource

## A collection of named stars the player can learn and navigate by.
##
## Author this as a .tres file in the editor, or build one at runtime with
## StarCatalogBuilder. Keep it small — 30 to 60 entries is plenty for a
## wayfinding game. Every star in here is a gameplay object, not decoration.

@export var stars: Array[StarEntry] = []


func find_by_id(id: String) -> StarEntry:
	for s in stars:
		if s and s.id == id:
			return s
	return null


func set_learned(id: String, value: bool = true) -> void:
	var s := find_by_id(id)
	if s:
		s.learned = value
