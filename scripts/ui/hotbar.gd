class_name Hotbar
extends HBoxContainer
## The row of round hotbar slots at the bottom of the screen (first slots of the player's Inventory).
## Click a slot or press 1–8 to select it.

var inventory: Inventory
var slots: Array[ItemSlotView] = []


func bind(target: Inventory) -> void:
	inventory = target
	for child in get_children():
		child.queue_free()
	slots.clear()
	add_theme_constant_override("separation", 14)
	for i in inventory.hotbar_size:
		var view := ItemSlotView.new()
		view.slot = i
		view.set_key_label(str(i + 1))
		view.pressed.connect(func() -> void: inventory.select(i))
		add_child(view)
		slots.append(view)
	inventory.changed.connect(func(_slot: int) -> void: refresh())
	inventory.selection_changed.connect(func(_slot: int) -> void: refresh())
	refresh()


func refresh() -> void:
	for view in slots:
		view.show_item(inventory.get_item(view.slot), inventory.get_count(view.slot))
		view.set_highlight(view.slot == inventory.selected)
