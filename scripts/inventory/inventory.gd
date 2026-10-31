class_name Inventory
extends Node
## A fixed number of item slots. The first `hotbar_size` slots are the hotbar.
##
## Each slot is either empty or holds one item id and a count (1..max_stack). Systems change the
## inventory only through these methods so the `changed` signal always fires and the UI stays right.

## Emitted when any slot changes (index of the slot, or -1 for many).
signal changed(slot: int)
## Emitted when the selected hotbar slot changes.
signal selection_changed(slot: int)
## Emitted when items are added (for pickup messages).
signal item_added(item: ItemData, count: int)

@export_range(1, 64) var size: int = 24
@export_range(1, 10) var hotbar_size: int = 8
## Given once when the inventory is created for a new game: item id -> count.
@export var starting_items: Dictionary = {}

var selected: int = 0

var _ids: Array[StringName] = []
var _counts: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	add_to_group("inventory")
	if get_parent() is PlayerController:
		add_to_group("player_inventory")
	clear()
	for id: StringName in starting_items:
		add_item(ItemRegistry.get_item(id), int(starting_items[id]))


func clear() -> void:
	_ids.resize(size)
	_ids.fill(&"")
	_counts.resize(size)
	_counts.fill(0)
	changed.emit(-1)


func get_item(slot: int) -> ItemData:
	return ItemRegistry.get_item(_ids[slot]) if is_valid_slot(slot) and _ids[slot] != &"" else null


func get_count(slot: int) -> int:
	return _counts[slot] if is_valid_slot(slot) else 0


func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < size


func is_empty_slot(slot: int) -> bool:
	return _ids[slot] == &""


## Total count of an item across all slots.
func count_of(item: ItemData) -> int:
	var total := 0
	if item:
		for i in size:
			if _ids[i] == item.id:
				total += _counts[i]
	return total


func has(item: ItemData, count: int = 1) -> bool:
	return count_of(item) >= count


## Adds items, filling existing stacks first (hotbar first), then empty slots.
## Returns how many did not fit (0 = all added).
func add_item(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	var left := count
	for i in size:
		if left == 0:
			break
		if _ids[i] == item.id and _counts[i] < item.max_stack:
			var put := mini(left, item.max_stack - _counts[i])
			_counts[i] += put
			left -= put
			changed.emit(i)
	for i in size:
		if left == 0:
			break
		if _ids[i] == &"":
			var put := mini(left, item.max_stack)
			_ids[i] = item.id
			_counts[i] = put
			left -= put
			changed.emit(i)
	if left < count:
		item_added.emit(item, count - left)
	return left


## True if `count` of the item would fit.
func can_add(item: ItemData, count: int = 1) -> bool:
	var room := 0
	for i in size:
		if _ids[i] == &"":
			room += item.max_stack
		elif _ids[i] == item.id:
			room += item.max_stack - _counts[i]
		if room >= count:
			return true
	return false


## Removes items, taking from the last stacks first. Returns false (and removes nothing) if there are not enough.
func remove_item(item: ItemData, count: int = 1) -> bool:
	if item == null or count_of(item) < count:
		return false
	var left := count
	for i in range(size - 1, -1, -1):
		if left == 0:
			break
		if _ids[i] == item.id:
			var take := mini(left, _counts[i])
			_counts[i] -= take
			left -= take
			if _counts[i] == 0:
				_ids[i] = &""
			changed.emit(i)
	return true


## Removes up to `count` from one slot. Returns how many were removed.
func take_from_slot(slot: int, count: int) -> int:
	if not is_valid_slot(slot) or _ids[slot] == &"":
		return 0
	var take := mini(count, _counts[slot])
	_counts[slot] -= take
	if _counts[slot] == 0:
		_ids[slot] = &""
	changed.emit(slot)
	return take


## Moves the stack in `from` onto `to`: merges when it is the same item, otherwise swaps.
func move_slot(from: int, to: int) -> void:
	if from == to or not is_valid_slot(from) or not is_valid_slot(to) or _ids[from] == &"":
		return
	if _ids[to] == _ids[from]:
		var item := get_item(from)
		var put := mini(_counts[from], item.max_stack - _counts[to])
		_counts[to] += put
		_counts[from] -= put
		if _counts[from] == 0:
			_ids[from] = &""
	else:
		var id := _ids[to]
		var n := _counts[to]
		_ids[to] = _ids[from]
		_counts[to] = _counts[from]
		_ids[from] = id
		_counts[from] = n
	changed.emit(from)
	changed.emit(to)


# --- Hotbar -----------------------------------------------------------------------------------------

func select(slot: int) -> void:
	slot = clampi(slot, 0, hotbar_size - 1)
	if slot != selected:
		selected = slot
		selection_changed.emit(slot)


func get_selected_item() -> ItemData:
	return get_item(selected)


# --- Save data --------------------------------------------------------------------------------------

## {"slots": [[id, count] or null, ...], "selected": n}
func to_dict() -> Dictionary:
	var slots := []
	for i in size:
		slots.append(null if _ids[i] == &"" else [String(_ids[i]), _counts[i]])
	return {"slots": slots, "selected": selected}


func from_dict(data: Dictionary) -> void:
	clear()
	var slots: Array = data.get("slots", [])
	for i in mini(slots.size(), size):
		var entry = slots[i]
		if entry is Array and entry.size() == 2 and ItemRegistry.has_item(StringName(entry[0])):
			_ids[i] = StringName(entry[0])
			_counts[i] = clampi(int(entry[1]), 1, ItemRegistry.get_item(_ids[i]).max_stack)
	selected = clampi(int(data.get("selected", 0)), 0, hotbar_size - 1)
	changed.emit(-1)
	selection_changed.emit(selected)
