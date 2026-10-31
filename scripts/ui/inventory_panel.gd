class_name InventoryPanel
extends Control
## The bag screen (Tab or I): every slot of the player's Inventory in a grid.
##
## Click a slot to pick up its stack (green ring), then click another slot to move it there
## (stacks merge, different items swap). Shift-click moves a stack between the hotbar row and the
## bag. The player does not move while the bag is open; Tab, I or Esc closes it.

signal opened_changed(is_open: bool)

const COLUMNS := 8

var inventory: Inventory
var slots: Array[ItemSlotView] = []
var held_slot: int = -1

var _title: Label
var _info: Label


func bind(target: Inventory) -> void:
	inventory = target
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.14, 0.1, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffaf0")
	style.border_color = Color("3d2a20")
	style.set_border_width_all(4)
	style.set_corner_radius_all(28)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	style.shadow_color = Color(0.35, 0.18, 0.12, 0.3)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_title = Label.new()
	_title.text = "Bag"
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color("3d2a20"))
	column.add_child(_title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for i in inventory.size:
		var view := ItemSlotView.new()
		view.slot = i
		if i < inventory.hotbar_size:
			view.set_key_label(str(i + 1))
		view.pressed.connect(_on_slot_pressed.bind(i))
		view.mouse_entered.connect(_on_slot_hovered.bind(i))
		grid.add_child(view)
		slots.append(view)
	_info = Label.new()
	_info.custom_minimum_size = Vector2(0, 56)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", Color("6b4a35"))
	_info.text = "Top row = hotbar (1–8).  Click to pick up and place.  Shift-click to move between hotbar and bag."
	column.add_child(_info)
	inventory.changed.connect(func(_slot: int) -> void: refresh())
	inventory.selection_changed.connect(func(_slot: int) -> void: refresh())
	refresh()


func is_open() -> bool:
	return visible


func toggle() -> void:
	set_open(not visible)


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	held_slot = -1
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player:
		player.input_enabled = not open
	refresh()
	opened_changed.emit(open)


func refresh() -> void:
	for view in slots:
		view.show_item(inventory.get_item(view.slot), inventory.get_count(view.slot))
		view.set_highlight(view.slot == inventory.selected, view.slot == held_slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not GameManager.is_paused():
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _on_slot_pressed(slot: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and not inventory.is_empty_slot(slot):
		quick_move(slot)
		return
	if held_slot < 0:
		if not inventory.is_empty_slot(slot):
			held_slot = slot
	else:
		inventory.move_slot(held_slot, slot)
		held_slot = -1
	refresh()


## Move a stack from the hotbar row to the first free bag slot, or the other way round.
func quick_move(slot: int) -> void:
	var to_bag := slot < inventory.hotbar_size
	var start := inventory.hotbar_size if to_bag else 0
	var end := inventory.size if to_bag else inventory.hotbar_size
	for i in range(start, end):
		if inventory.is_empty_slot(i) or inventory.get_item(i) == inventory.get_item(slot):
			inventory.move_slot(slot, i)
			if inventory.is_empty_slot(slot):
				break
	held_slot = -1
	refresh()


func _on_slot_hovered(slot: int) -> void:
	var item := inventory.get_item(slot)
	if item:
		_info.text = "%s — %s" % [item.display_name, item.description]
