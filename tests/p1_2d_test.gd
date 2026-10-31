extends Node
## Automated check for the 2D isometric foundation (P1-2D + isometric view).
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
	_check("smooth art: linear mipmap texture filter", int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) == 3)
	_check("renderer is Compatibility", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility")

	world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	add_child(world)
	await _frames(3)
	player = world.get_player()
	var camera := world.camera
	print("  world built in %d ms: %s" % [world.build_msec, _summary()])
	_check("map is 320 × 320 tiles", world.ground.get_used_rect().size == Vector2i(320, 320), str(world.ground.get_used_rect()))
	_check("world builds in under 4 s", world.build_msec < 4000, "%d ms" % world.build_msec)
	_check("camera at 1:1 (128 × 64 px tiles)", camera.zoom == Vector2(1, 1))
	_check("14 buildings (all but the well) and 12 village houses are drawn", _count_prefix("house_") == 26, str(_count_prefix("house_")))
	_check("a sign is drawn for every sign", world.objects.counts.get("sign", 0) == world.get_node("Sim/Signs").get_child_count())
	_check("Westwood is wooded (≥ 1500 trees)", _count_prefix("tree_") >= 1500, str(_count_prefix("tree_")))
	var bad := 0
	for p: Vector2 in world.objects.obstacle_positions:
		if world.ground.get_cell_atlas_coords(world.ground.local_to_map(p)) != WorldManager.GRASS:
			bad += 1
	_check("no tree or rock stands on a road, water or a building", bad == 0, str(bad))
	var spawn := world.layout.get_player_spawn()
	_check("player spawns at the blueprint spawn", player.global_position.distance_to(WorldLayout.to_pixels(spawn.x, spawn.z)) < 1.0)
	_check("spawn tile is walkable", not world.is_blocked(player.global_position))
	_check("player sprite stands at the body's view position", world.player_sprite.position.distance_to(WorldLayout.to_view(player.global_position)) < 0.5)

	# Screen-relative controls: W walks up the screen (north-west on the ground).
	var before := player.global_position
	await _move_for(Vector2.UP, false, 0.5)
	var moved := (player.global_position - before).normalized()
	_check("W walks up the screen (north-west on the map)", moved.dot(Vector2(-1, -1).normalized()) > 0.95, str(moved))
	var view_moved := WorldLayout.to_view(player.global_position) - WorldLayout.to_view(before)
	_check("…which is straight up in the view", absf(view_moved.normalized().x) < 0.08 and view_moved.y < 0.0, str(view_moved))
	_check("camera follows the player", camera.position.distance_to(world.player_sprite.position) < 120.0, str(camera.position))

	# Walking and running speed (tiles per second), 8 directions at the same speed.
	var walk := await _move_for(Vector2.RIGHT, false, 1.0)
	_check("walks about 5 tiles/s", absf(walk - 5.0) < 0.6, "%.2f tiles/s" % walk)
	_check("walk animation faces right", world.player_sprite.animation == "walk_right", world.player_sprite.animation)
	await _frames(20)
	_check("idle animation after stopping", world.player_sprite.animation == "idle_right", world.player_sprite.animation)
	var run := await _move_for(Vector2.LEFT, true, 1.0)
	_check("runs about 8 tiles/s", absf(run - 8.0) < 0.9, "%.2f tiles/s" % run)
	var diagonal := await _move_for(Vector2(1, 1), false, 1.0)
	_check("diagonal is not faster", absf(diagonal - walk) < 0.4, "%.2f vs %.2f" % [diagonal, walk])
	await _move_for(Vector2.UP, false, 0.3)
	_check("faces up when walking up", player.direction_name() == "up")

	# Water and buildings block (moving along map axes for these checks).
	player.input_transform = Transform2D.IDENTITY
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
	var trunk: Vector2 = world.objects.obstacle_positions[0]
	player.teleport(trunk + Vector2(-20, 0), Vector2.RIGHT)
	await _move_for(Vector2.RIGHT, false, 1.0)
	_check("tree trunks block the player", player.global_position.x < trunk.x - 3.0, "%s vs trunk %s" % [player.global_position, trunk])
	player.input_transform = WorldLayout.screen_to_ground()

	# Interaction: the farm well sign.
	var sign := world.get_node("Sim/Signs/Sign_well") as InfoSign
	player.input_transform = Transform2D.IDENTITY
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
	player.input_transform = WorldLayout.screen_to_ground()

	# Regions
	player.teleport(WorldLayout.to_pixels(-380, 0), Vector2.DOWN)
	await _frames(4)
	_check("Westwood Forest region is reported", _regions.has("forest"), str(_regions))
	player.teleport(WorldLayout.to_pixels(0, 30), Vector2.DOWN)
	await _frames(4)
	_check("Haven Village region is reported", _regions.has("village"), str(_regions))

	# Camera stays inside its limits at the top corner of the island.
	player.teleport(Vector2(24, 24), Vector2.DOWN)
	await _frames(40)
	var centre := camera.get_screen_center_position()
	_check("camera stays inside the map limits at the corner", centre.y >= camera.limit_top + 539.0, str(centre))

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


func _count_prefix(prefix: String) -> int:
	var total := 0
	for art: String in world.objects.counts:
		if art.begins_with(prefix):
			total += world.objects.counts[art]
	return total


func _summary() -> String:
	return "%d buildings, %d trees, %d other objects" % [_count_prefix("house_"), _count_prefix("tree_"),
		world.objects.get_child_count() - _count_prefix("house_") - _count_prefix("tree_")]


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
