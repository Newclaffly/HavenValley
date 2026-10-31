extends CanvasLayer
## Pause overlay. Shown and hidden by GameManager through EventBus.game_paused.
## Runs while the tree is paused (process_mode = Always in the scene).

@onready var _resume_button: Button = %ResumeButton
@onready var _menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	EventBus.game_paused.connect(_on_game_paused)
	_resume_button.pressed.connect(GameManager.set_paused.bind(false))
	_menu_button.pressed.connect(GameManager.return_to_main_menu)
	_quit_button.pressed.connect(GameManager.quit_game)


func _on_game_paused(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		_resume_button.grab_focus()
