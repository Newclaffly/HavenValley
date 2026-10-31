class_name ToolUser
extends Node
## Uses the item selected in the hotbar: picks hotbar slots with 1–8 and swings the selected tool
## with the left mouse button (or F) at the tree or rock in front of the player.
##
## Child of the Player. Needs the player's Inventory (Player/Inventory) and a HarvestSystem in the
## "harvest_system" group.

@export var swing_cooldown: float = 0.4
## The target point is this far in front of the player (map pixels)…
@export var reach_forward: float = 9.0
## …and anything within this radius of it can be hit.
@export var reach_radius: float = 10.0

var current_target: String = ""

var _cooldown: float = 0.0
var _player: PlayerController
var _inventory: Inventory
var _prompt: String = ""


func _ready() -> void:
	_player = get_parent() as PlayerController
	_inventory = _player.get_node("Inventory") as Inventory


func _unhandled_input(event: InputEvent) -> void:
	if not _player.input_enabled:
		return
	for i in _inventory.hotbar_size:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_inventory.select(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("use_tool"):
		use_selected()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	_update_target()


## Swing the selected tool. Returns hits left on the target, or -1 when nothing was hit.
func use_selected() -> int:
	if _cooldown > 0.0:
		return -1
	var item := _inventory.get_selected_item()
	if item == null or not item.is_tool():
		return -1
	_cooldown = swing_cooldown
	var sprite := get_tree().get_first_node_in_group("player_sprite") as CharacterSprite
	if sprite:
		sprite.play_swing()
	var harvest := get_tree().get_first_node_in_group("harvest_system") as HarvestSystem
	if harvest == null:
		return -1
	var target := harvest.find_target(item.tool_type, reach_point(), reach_radius)
	return harvest.hit(target) if target != "" else -1


## Map position in front of the player that tools reach.
func reach_point() -> Vector2:
	return _player.global_position + _player.ground_facing() * reach_forward


func _update_target() -> void:
	var item := _inventory.get_selected_item()
	var harvest := get_tree().get_first_node_in_group("harvest_system") as HarvestSystem
	var text := ""
	current_target = ""
	if item and item.is_tool() and harvest:
		current_target = harvest.find_target(item.tool_type, reach_point(), reach_radius)
		if current_target != "":
			var verb := "Chop" if item.tool_type == ItemData.ToolType.AXE else "Mine"
			text = "%s %s" % [verb, harvest.describe(current_target)]
	if text != _prompt:
		_prompt = text
		EventBus.tool_target_changed.emit(text)
