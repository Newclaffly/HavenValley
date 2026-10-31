@tool
class_name Interactable
extends Area2D
## Something the player can use with the interact key (E).
##
## Add this node (or a subclass) to any object and give it a CollisionShape2D child.
## The player's InteractionDetector finds it on physics layer 3 ("interactable").
## Subclasses override _on_interact(); other nodes can connect to the `interacted` signal instead.

## Emitted after the interaction has been handled.
signal interacted(interactor: Node)

const INTERACTABLE_LAYER := 1 << 2  # Physics layer 3 "interactable".

## Text shown after "[E]" on the HUD, for example "Read sign".
@export var prompt: String = "Interact"
## Turn off to make the object ignore the player without removing it.
@export var enabled: bool = true


func _init() -> void:
	# Defaults only. Values saved in a scene are applied after _init and still win.
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func can_interact() -> bool:
	return enabled


func interact(interactor: Node) -> void:
	if not can_interact():
		return
	_on_interact(interactor)
	interacted.emit(interactor)
	EventBus.interacted.emit(self, interactor)


## Override in subclasses.
func _on_interact(_interactor: Node) -> void:
	pass
