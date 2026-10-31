extends Control
## Title screen: New Game, Continue and Quit.

@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _quit_button: Button = %QuitButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	GameManager.enter_main_menu()
	_new_game_button.pressed.connect(GameManager.start_new_game)
	_quit_button.pressed.connect(GameManager.quit_game)
	# Saving and loading arrive in Phase 6; until then there is nothing to continue.
	_continue_button.disabled = true
	_continue_button.tooltip_text = "Saving arrives in Phase 6."
	_version_label.text = "v%s · Phase 1 prototype" % ProjectSettings.get_setting("application/config/version", "0.1.0")
	_new_game_button.grab_focus()
