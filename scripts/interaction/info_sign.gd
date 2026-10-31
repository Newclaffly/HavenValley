@tool
class_name InfoSign
extends Interactable
## A readable sign. Interacting shows its title and message as a HUD notification.

@export var title: String = "Sign"
@export_multiline var message: String = ""


func _init() -> void:
	super._init()
	prompt = "Read sign"


func _on_interact(_interactor: Node) -> void:
	EventBus.notification_requested.emit(title, message)
