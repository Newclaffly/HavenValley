extends Node
## High-level game state (autoload "GameManager").
##
## Owns which top-level scene is running, pausing, and the mouse mode that goes with each state.
## It never touches gameplay objects directly.

enum State { MAIN_MENU, PLAYING, PAUSED }

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

var state: State = State.MAIN_MENU


func _ready() -> void:
	# Keep listening for the pause key while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state != State.MAIN_MENU:
		toggle_pause()
		get_viewport().set_input_as_handled()


## Load the world and start playing.
func start_new_game() -> void:
	_change_scene(WORLD_SCENE)


## Called by the world scene once it is ready, including when it is run directly from the editor (F6).
func enter_gameplay() -> void:
	get_tree().paused = false
	state = State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Called by the main menu scene when it opens.
func enter_main_menu() -> void:
	get_tree().paused = false
	state = State.MAIN_MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func return_to_main_menu() -> void:
	_change_scene(MAIN_MENU_SCENE)


func is_paused() -> bool:
	return state == State.PAUSED


func toggle_pause() -> void:
	set_paused(state != State.PAUSED)


func set_paused(paused: bool) -> void:
	if state == State.MAIN_MENU:
		return
	if paused == (state == State.PAUSED):
		return
	state = State.PAUSED if paused else State.PLAYING
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	EventBus.game_paused.emit(paused)


func quit_game() -> void:
	get_tree().quit()


func _change_scene(path: String) -> void:
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("GameManager: could not load scene %s (error %d)" % [path, error])
