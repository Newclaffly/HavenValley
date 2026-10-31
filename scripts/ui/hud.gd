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


func _ready() -> void:
	_prompt_panel.visible = false
	_notification_panel.visible = false
	EventBus.interaction_target_changed.connect(_on_interaction_target_changed)
	EventBus.notification_requested.connect(_on_notification_requested)
	EventBus.player_chunk_changed.connect(_on_player_chunk_changed)
	EventBus.region_changed.connect(_on_region_changed)
	_region_banner.modulate.a = 0.0


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
	_prompt_panel.visible = not prompt.is_empty()
	_prompt_label.text = "[E]  %s" % prompt


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
		var p := player.global_position
		lines.append("Position  x %.1f  y %.1f  z %.1f" % [p.x, p.y, p.z])
		lines.append("Chunk %s   Speed %.1f m/s   %s" % [_chunk, player.get_horizontal_speed(), "on ground" if player.is_on_floor() else "in air"])
	lines.append("F3 hide")
	_debug_label.text = "\n".join(lines)
