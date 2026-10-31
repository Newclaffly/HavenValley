extends Node
## Automated Phase 1 check. Loads the world, drives the player with simulated input and checks the
## results. Run from the project folder:
##
##   godot --headless --path . res://tests/phase1_test.tscn --fixed-fps 60
##
## Or open tests/phase1_test.tscn in the editor and press F6. The exit code is 0 when every check passes.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _passed: int = 0
var _failed: int = 0
var _notifications: Array[String] = []
var _prompts: Array[String] = []


func _ready() -> void:
	# The test runner must keep running while the game is paused; the world must not.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.notification_requested.connect(func(title: String, _message: String) -> void: _notifications.append(title))
	EventBus.interaction_target_changed.connect(func(prompt: String) -> void: _prompts.append(prompt))
	_run.call_deferred()


func _run() -> void:
	print("--- Haven Valley Phase 1 test (Godot %s) ---" % Engine.get_version_info().string)
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await _physics_frames(5)
	var player := world.get_player()
	var layout := world.layout

	# World and spawn
	_check("world layout loaded", layout.is_valid())
	_check("greybox landmarks, village, bridges, docks, edges built", world.get_node("Greybox").get_child_count() >= 5)
	_check("town hall exists", world.get_node_or_null("Greybox/Landmarks/town_hall") != null)
	var sign_count := 0
	for node in world.get_node("Greybox/Landmarks").get_children():
		if node is InfoSign:
			sign_count += 1
	_check("a sign at every landmark (except spawn, lake, residential area)", sign_count == layout.get_landmarks().size() - 3, "%d signs" % sign_count)
	var spawn := player.global_position
	_check("player spawns at blueprint spawn (-152, 182)", Vector2(spawn.x, spawn.z).distance_to(Vector2(-152, 182)) < 0.5, str(spawn))
	_check("game state is PLAYING", GameManager.state == GameManager.State.PLAYING)
	_check("spawn chunk is C6", world.current_chunk == "C6", world.current_chunk)
	await _physics_frames(20)
	_check("player stands on the ground", player.is_on_floor())

	# Walking: camera-relative, toward the Town Hall at spawn
	var start := player.global_position
	Input.action_press("move_forward")
	await _physics_frames(120)
	var walked := player.global_position - start
	_check("walks about 4 m/s", walked.length() > 6.5 and walked.length() < 8.5, "%.2f m in 2 s" % walked.length())
	var to_hall := (Vector3(0, 0, -24) - start)
	to_hall.y = 0.0
	_check("forward walks toward the Town Hall", walked.normalized().dot(to_hall.normalized()) > 0.98)

	# Running
	Input.action_press("run")
	await _physics_frames(30)
	_check("runs at 7 m/s", absf(player.get_horizontal_speed() - 7.0) < 0.2, "%.2f m/s" % player.get_horizontal_speed())
	Input.action_release("run")
	Input.action_release("move_forward")
	await _physics_frames(30)
	_check("stops when keys are released", player.get_horizontal_speed() < 0.05)

	# Jumping
	var ground_y := player.global_position.y
	Input.action_press("jump")
	await _physics_frames(2)
	Input.action_release("jump")
	var peak := ground_y
	for i in 90:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_check("jump reaches about 1.2 m", absf(peak - ground_y - 1.2) < 0.15, "%.2f m" % (peak - ground_y))
	_check("lands again", player.is_on_floor())

	# Interaction with the well sign
	var well_sign := world.get_node("Greybox/Landmarks/Sign_well") as InfoSign
	_check("well sign exists", well_sign != null)
	if well_sign:
		player.teleport(well_sign.global_position + Vector3(0, 0, 2.0), well_sign.global_position)
		await _physics_frames(5)
		var detector := player.get_node("Model/InteractionDetector") as InteractionDetector
		_check("detector picks the well sign", detector.current == well_sign, str(detector.current))
		_check("HUD receives 'Read sign' prompt", not _prompts.is_empty() and _prompts[-1] == "Read sign")
		var press := InputEventAction.new()
		press.action = "interact"
		press.pressed = true
		Input.parse_input_event(press)
		await _physics_frames(3)
		_check("pressing E shows the sign's notification", _notifications.has("Water Well"), str(_notifications))
		var hud_title := world.get_node("HUD/Root/NotificationStrip/NotificationPanel/Column/NotificationTitle") as Label
		_check("HUD notification shows the title", hud_title.is_visible_in_tree() and hud_title.text == "Water Well")
		player.teleport(well_sign.global_position + Vector3(0, 0, 25), well_sign.global_position + Vector3(0, 0, 50))
		await _physics_frames(5)
		_check("prompt clears when walking away", _prompts[-1] == "")

	# Camera collision: stand just south of the Town Hall facing south, so the camera would be inside it.
	player.teleport(world.ground_at(0, -13.5) + Vector3.UP * 0.05, Vector3(0, 10, 20))
	await _physics_frames(10)
	var camera := (player.get_node("CameraRig") as PlayerCameraRig).get_camera()
	# The hall's front wall is at z = -18 (3 m behind the footprint edge, behind the portico columns).
	_check("camera is pushed out of the Town Hall wall", camera.global_position.z > -18.0, str(camera.global_position))
	_check("camera is the active camera", camera.is_current())

	# Pause
	GameManager.set_paused(true)
	await get_tree().process_frame
	_check("pause stops the game", get_tree().paused and GameManager.is_paused())
	_check("pause menu is visible", (world.get_node("PauseMenu") as CanvasLayer).visible)
	var paused_at := player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.3, true).timeout
	Input.action_release("move_forward")
	_check("player does not move while paused", player.global_position.is_equal_approx(paused_at))
	GameManager.set_paused(false)
	await get_tree().process_frame
	_check("resume unpauses", not get_tree().paused and not (world.get_node("PauseMenu") as CanvasLayer).visible)

	# Chunk tracking
	player.teleport(world.ground_at(0, -8) + Vector3.UP * 0.05, Vector3(0, 10, -100))
	await _physics_frames(3)
	_check("Town Hall is in chunk E4", world.current_chunk == "E4", world.current_chunk)

	print("--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  ", label)
	else:
		_failed += 1
		print("  FAIL  ", label, ("  (" + detail + ")") if not detail.is_empty() else "")


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
