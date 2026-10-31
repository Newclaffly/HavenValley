extends Node
## Every ItemData in res://resources/items/, looked up by id (autoload "ItemRegistry").

const ITEMS_DIR := "res://resources/items"

var _items: Dictionary = {}  # StringName -> ItemData


func _ready() -> void:
	reload()


func reload() -> void:
	_items.clear()
	# list_directory also works in exported games, where .tres files are remapped.
	for file: String in ResourceLoader.list_directory(ITEMS_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var item := load(ITEMS_DIR.path_join(file)) as ItemData
		if item == null:
			push_warning("ItemRegistry: %s is not an ItemData." % file)
			continue
		if item.id != StringName(file.get_basename()):
			push_warning("ItemRegistry: %s has id '%s'; the id must match the file name." % [file, item.id])
		_items[item.id] = item


## The item with this id, or null.
func get_item(id: StringName) -> ItemData:
	return _items.get(id)


func has_item(id: StringName) -> bool:
	return _items.has(id)


func all_ids() -> Array:
	return _items.keys()
