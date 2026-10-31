@tool
class_name InfoSign
extends Interactable
## A sign that shows a title and message on the HUD when read.

@export var title: String = ""
@export_multiline var message: String = ""


func _init() -> void:
	super()
	prompt = "Read sign"


func _on_interact(_interactor: Node) -> void:
	EventBus.notification_requested.emit(title, message)
