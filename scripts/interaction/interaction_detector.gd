class_name InteractionDetector
extends Area2D
## Finds the best Interactable in front of the player and uses it when "interact" is pressed.
##
## Put this Area2D under the player's Facing node with a CollisionShape2D a little in front
## (Facing's +Y points where the player looks). The Player root is passed to interact().

## How strongly facing an object beats being close to it, in pixels of distance.
@export var facing_weight: float = 12.0

var current: Interactable = null

var _candidates: Array[Interactable] = []


func _init() -> void:
	collision_layer = 0
	collision_mask = Interactable.INTERACTABLE_LAYER
	monitoring = true
	monitorable = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(_delta: float) -> void:
	var best := _pick_best()
	if best != current:
		current = best
		EventBus.interaction_target_changed.emit(best.prompt if best else "")


func _unhandled_input(event: InputEvent) -> void:
	if current and event.is_action_pressed("interact"):
		var player := owner as PlayerController
		if player and not player.input_enabled:
			return
		current.interact(owner)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if current:
		current = null
		EventBus.interaction_target_changed.emit("")


func _on_area_entered(area: Area2D) -> void:
	if area is Interactable and not _candidates.has(area):
		_candidates.append(area as Interactable)


func _on_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_candidates.erase(area as Interactable)


func _pick_best() -> Interactable:
	var origin: Vector2 = (owner as Node2D).global_position if owner is Node2D else global_position
	var forward: Vector2 = (get_parent() as Node2D).global_transform.y.normalized() if get_parent() is Node2D else Vector2.DOWN
	var best: Interactable = null
	var best_score := INF
	for candidate in _candidates:
		if not is_instance_valid(candidate) or not candidate.can_interact():
			continue
		var to_target := candidate.global_position - origin
		var distance := to_target.length()
		var facing: float = 1.0 if distance < 0.01 else forward.dot(to_target / distance)
		var score: float = distance - facing * facing_weight
		if score < best_score:
			best_score = score
			best = candidate
	return best
