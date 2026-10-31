extends CanvasLayer
## In-game HUD: the "[E] …" interaction prompt, short notifications, and a debug readout (F3).
## Listens to EventBus only, so it can be removed or replaced without touching gameplay code.

## Seconds a notification stays on screen.
@export var notification_duration: float = 4.0

var _notification_time_left: float = 0.0
var _chunk: String = "—"

@onready var _prompt_panel: Control = %PromptPanel
@onready var _prompt_label: Label = %PromptLabel
@onready var _notification_panel: Control = %NotificationPanel
@onready var _notification_title: Label = %NotificationTitle
@onready var _notification_message: Label = %NotificationMessage
@onready var _debug_label: Label = %DebugLabel
@onready var _region_banner: Label = %RegionBanner

var _banner_tween: Tween
var _interaction_prompt: String = ""
var _tool_prompt: String = ""

## Built in code in _ready (Phase 3A).
var hotbar: Hotbar
var inventory_panel: InventoryPanel
var _toasts: VBoxContainer


func _ready() -> void:
	_prompt_panel.visible = false
	_notification_panel.visible = false
	EventBus.interaction_target_changed.connect(_on_interaction_target_changed)
	EventBus.notification_requested.connect(_on_notification_requested)
	EventBus.player_chunk_changed.connect(_on_player_chunk_changed)
	EventBus.region_changed.connect(_on_region_changed)
	EventBus.tool_target_changed.connect(_on_tool_target_changed)
	_region_banner.modulate.a = 0.0
	_build_inventory_ui()


func _build_inventory_ui() -> void:
	var inventory := get_tree().get_first_node_in_group("player_inventory") as Inventory
	if inventory == null:
		return
	var root := $Root as Control
	var strip := CenterContainer.new()
	strip.name = "HotbarStrip"
	strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	strip.anchor_left = 0.0
	strip.anchor_right = 1.0
	strip.offset_top = -112
	strip.offset_bottom = -18
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	hotbar = Hotbar.new()
	hotbar.name = "Hotbar"
	strip.add_child(hotbar)
	hotbar.bind(inventory)
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toasts.offset_left = -330
	_toasts.offset_right = -30
	_toasts.offset_top = -340
	_toasts.offset_bottom = -130
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)
	inventory.item_added.connect(_on_item_added)
	inventory_panel = InventoryPanel.new()
	inventory_panel.name = "InventoryPanel"
	root.add_child(inventory_panel)
	inventory_panel.bind(inventory)


var _toast_rows: Dictionary = {}  # item id -> [row, label, total, tween]


func _on_item_added(item: ItemData, count: int) -> void:
	# Several pickups of the same item in quick succession add up in one line ("+4 Wood").
	if _toast_rows.has(item.id) and is_instance_valid(_toast_rows[item.id][0]):
		var entry: Array = _toast_rows[item.id]
		entry[2] += count
		(entry[1] as Label).text = "+%d %s" % [entry[2], item.display_name]
		(entry[3] as Tween).kill()
		(entry[0] as Control).modulate.a = 1.0
		entry[3] = _fade_toast(entry[0], item.id)
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = "+%d %s" % [count, item.display_name]
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("fffaf0"))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color("3d2a20"))
	row.add_child(label)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	_toasts.add_child(row)
	_toast_rows[item.id] = [row, label, count, _fade_toast(row, item.id)]


func _fade_toast(row: Control, id: StringName) -> Tween:
	var tween := row.create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void:
		_toast_rows.erase(id)
		row.queue_free())
	return tween


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _notification_panel.visible:
		_notification_time_left -= delta
		if _notification_time_left <= 0.0:
			_notification_panel.visible = false
	if _debug_label.visible:
		_update_debug()


func _on_interaction_target_changed(prompt: String) -> void:
	_interaction_prompt = prompt
	_update_prompt()


func _on_tool_target_changed(prompt: String) -> void:
	_tool_prompt = prompt
	_update_prompt()


## The hand prompt ("[E] …") wins over the tool prompt ("[Click] …").
func _update_prompt() -> void:
	if not _interaction_prompt.is_empty():
		_prompt_label.text = "[E]  %s" % _interaction_prompt
	elif not _tool_prompt.is_empty():
		_prompt_label.text = "[Click]  %s" % _tool_prompt
	_prompt_panel.visible = not (_interaction_prompt.is_empty() and _tool_prompt.is_empty())


func _on_notification_requested(title: String, message: String) -> void:
	_notification_title.text = title
	_notification_title.visible = not title.is_empty()
	_notification_message.text = message
	_notification_panel.visible = true
	_notification_time_left = notification_duration


## Shows the region name in large text for a few seconds when the player enters a region.
func _on_region_changed(_region_id: String, region_name: String) -> void:
	if region_name.is_empty():
		return
	_region_banner.text = region_name
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_region_banner, "modulate:a", 1.0, 0.6)
	_banner_tween.tween_interval(2.4)
	_banner_tween.tween_property(_region_banner, "modulate:a", 0.0, 1.0)


func _on_player_chunk_changed(chunk: String) -> void:
	_chunk = chunk


func _update_debug() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	var lines := PackedStringArray()
	lines.append("FPS %d" % Engine.get_frames_per_second())
	if player:
		var tile := WorldLayout.to_tile(player.global_position)
		var m := WorldLayout.to_metres(player.global_position)
		lines.append("Tile %d, %d   (blueprint x %.0f  z %.0f)" % [tile.x, tile.y, m.x, m.z])
		lines.append("Chunk %s   Speed %.1f tiles/s   Facing %s" % [_chunk, player.get_speed_tiles(), player.direction_name()])
	lines.append("F3 hide")
	_debug_label.text = "\n".join(lines)
