class_name InteractionDetector
extends Area3D
## Finds the best Interactable in front of its owner and uses it when "interact" is pressed.
##
## Put this Area3D under the part of the character that turns to face the movement direction,
## with a CollisionShape3D placed in front of the character.
## The owner of the scene (the Player root) is passed to Interactable.interact() as the interactor.

## How strongly facing an object beats being close to it. 0 = nearest wins.
@export var facing_weight: float = 1.0

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
		current.interact(owner)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if current:
		current = null
		EventBus.interaction_target_changed.emit("")


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable and not _candidates.has(area):
		_candidates.append(area as Interactable)


func _on_area_exited(area: Area3D) -> void:
	if area is Interactable:
		_candidates.erase(area as Interactable)


func _pick_best() -> Interactable:
	var origin := global_position
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Interactable = null
	var best_score := INF
	for candidate in _candidates:
		if not is_instance_valid(candidate) or not candidate.can_interact():
			continue
		var to_target := candidate.global_position - origin
		to_target.y = 0.0
		var distance := to_target.length()
		var facing := 1.0 if distance < 0.01 else forward.dot(to_target / distance)
		var score := distance - facing * facing_weight
		if score < best_score:
			best_score = score
			best = candidate
	return best
