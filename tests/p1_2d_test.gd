extends Node
## Automated check for Phase P1-2D (2D foundation).
##
##   godot --headless --path . res://tests/p1_2d_test.tscn
##
## Or open tests/p1_2d_test.tscn and press F6. Exit code 0 when every check passes.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _passed: int = 0
var _failed: int = 0
var _prompts: Array[String] = []
var _notifications: Array[String] = []
var _regions: Array[String] = []
var world: WorldManager
var player: PlayerController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.interaction_target_changed.connect(func(p: String) -> void: _prompts.append(p))
	EventBus.notification_requested.connect(func(t: String, _m: String) -> void: _notifications.append(t))
	EventBus.region_changed.connect(func(id: String, _n: String) -> void: _regions.append(id))
	_run.call_deferred()


func _run() -> void:
	print("--- Haven Valley P1-2D test (Godot %s) ---" % Engine.get_version_info().string)
	_check("pixel art: nearest texture filter", int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) == 0)
	_check("renderer is Compatibility", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility")

	world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	add_child(world)
	await _frames(3)
	player = world.get_player()
	var camera := player.get_node("Camera") as Camera2D
	print("  greybox map built in %d ms" % world.build_msec)
	_check("map is 320 × 320 tiles", world.ground.get_used_rect().size == Vector2i(320, 320), str(world.ground.get_used_rect()))
	_check("map builds in under 3 s", world.build_msec < 3000, "%d ms" % world.build_msec)
	_check("camera shows 480 × 270 world pixels (zoom 4)", camera.zoom == Vector2(4, 4))
	var spawn := world.layout.get_player_spawn()
	_check("player spawns at the blueprint spawn", player.global_position.distance_to(WorldLayout.to_pixels(spawn.x, spawn.z)) < 1.0)
	_check("spawn tile is walkable", not world.is_blocked(player.global_position))

	# Walking and running speed (tiles per second), 8 directions at the same speed.
	var walk := await _move_for(Vector2.RIGHT, false, 1.0)
	_check("walks about 5 tiles/s", absf(walk - 5.0) < 0.6, "%.2f tiles/s" % walk)
	_check("walk animation faces right", player.get_node("Sprite").animation == "walk_right", player.get_node("Sprite").animation)
	await _frames(20)
	_check("idle animation after stopping", player.get_node("Sprite").animation == "idle_right", player.get_node("Sprite").animation)
	var run := await _move_for(Vector2.LEFT, true, 1.0)
	_check("runs about 8 tiles/s", absf(run - 8.0) < 0.9, "%.2f tiles/s" % run)
	var diagonal := await _move_for(Vector2(1, 1), false, 1.0)
	_check("diagonal is not faster", absf(diagonal - walk) < 0.4, "%.2f vs %.2f" % [diagonal, walk])
	await _move_for(Vector2.UP, false, 0.3)
	_check("faces up when walking up", player.direction_name() == "up")

	# Water and buildings block.
	var lake: Dictionary = world.layout.data["water"]["lake"]
	var shore := WorldLayout.to_pixels(lake["center"][0] - lake["radii"][0] - 8.0, lake["center"][2])
	player.teleport(shore, Vector2.RIGHT)
	await _move_for(Vector2.RIGHT, false, 2.0)
	_check("cannot walk into the lake", not world.is_blocked(player.global_position) and player.global_position.x < WorldLayout.to_pixels(lake["center"][0] - lake["radii"][0] + 4.0, 0).x,
		str(WorldLayout.to_metres(player.global_position)))
	var hall := WorldLayout.to_pixels(0, -24 + 9 + 6)
	player.teleport(hall, Vector2.UP)
	await _move_for(Vector2.UP, false, 2.0)
	_check("cannot walk through the Town Hall", player.global_position.y > WorldLayout.to_pixels(0, -24 + 9).y - 2.0, str(WorldLayout.to_metres(player.global_position)))

	# Interaction: the farm well sign.
	var sign := world.get_node("Signs/Sign_well") as InfoSign
	player.teleport(sign.global_position + Vector2(0, 14), Vector2.UP)
	await _frames(6)
	_check("standing at the well sign shows a prompt", _prompts.size() > 0 and _prompts[-1] == "Read sign", str(_prompts.slice(-3)))
	var hud_prompt := world.get_node("HUD/Root/PromptStrip/PromptPanel/PromptLabel") as Label
	_check("HUD shows [E] Read sign", hud_prompt.is_visible_in_tree() and hud_prompt.text == "[E]  Read sign", hud_prompt.text)
	_press("interact")
	await _frames(3)
	_check("pressing E reads the sign", _notifications.has("Water Well"), str(_notifications))
	player.teleport(sign.global_position + Vector2(0, 120), Vector2.DOWN)
	await _frames(6)
	_check("prompt clears when walking away", _prompts[-1] == "")

	# Regions
	player.teleport(WorldLayout.to_pixels(-380, 0), Vector2.DOWN)
	await _frames(4)
	_check("Westwood Forest region is reported", _regions.has("forest"), str(_regions))
	player.teleport(WorldLayout.to_pixels(0, 30), Vector2.DOWN)
	await _frames(4)
	_check("Haven Village region is reported", _regions.has("village"), str(_regions))

	# Camera stays inside the map at a corner.
	player.teleport(Vector2(24, 24), Vector2.DOWN)
	await _frames(30)
	var centre := camera.get_screen_center_position()
	_check("camera stays inside the map at the corner", centre.x >= 239.0 and centre.y >= 134.0, str(centre))

	# Pause
	_press("pause")
	await _frames(2)
	_check("Esc pauses the game", GameManager.is_paused() and get_tree().paused)
	_check("pause menu is shown", (world.get_node("PauseMenu") as CanvasLayer).visible)
	_press("pause")
	await _frames(2)
	_check("Esc again resumes", not GameManager.is_paused())

	print("--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Hold a direction (and run) for some seconds; returns average speed in tiles/s.
func _move_for(direction: Vector2, running: bool, seconds: float) -> float:
	var start := player.global_position
	var actions := []
	if direction.x > 0.0: actions.append("move_right")
	if direction.x < 0.0: actions.append("move_left")
	if direction.y > 0.0: actions.append("move_back")
	if direction.y < 0.0: actions.append("move_forward")
	if running: actions.append("run")
	for a: String in actions:
		Input.action_press(a)
	await _frames(6)  # reach full speed
	var measure_from := player.global_position
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var distance := player.global_position.distance_to(measure_from)
	for a: String in actions:
		Input.action_release(a)
	await _frames(2)
	if start == Vector2.INF:
		return 0.0
	return distance / t / WorldLayout.TILE_PX


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  [%s]" % [label, detail])
