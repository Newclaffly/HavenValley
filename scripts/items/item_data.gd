@tool
class_name ItemData
extends Resource
## Definition of one kind of item (a .tres file in res://resources/items/).
##
## Items are identified by `id`, which never changes once a save file can contain it. Inventories
## and save data store ids and counts, never the resource itself.

enum Category { RESOURCE, FORAGE, TOOL, SEED, CROP, BUILDING }
enum ToolType { NONE, AXE, PICKAXE, HOE, WATERING_CAN }

## Permanent id, lowercase with underscores, for example "wood". Must match the file name.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.RESOURCE
## Icon shown in the hotbar and inventory.
@export var icon: Texture2D
## Art name in assets/art (ArtLibrary) for this item lying on the ground, e.g. "item_wood".
@export var world_art: String = ""
## How many fit in one inventory slot. Tools are 1.
@export_range(1, 999) var max_stack: int = 99
@export var tool_type: ToolType = ToolType.NONE
## Price a shop pays for one (Phase 4 economy).
@export var sell_price: int = 0


func is_tool() -> bool:
	return tool_type != ToolType.NONE
