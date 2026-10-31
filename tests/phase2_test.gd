extends Node
## Automated Phase 2A check: terrain matches the blueprint and the world is walkable.
##
##   godot --headless --path . res://tests/phase2_test.tscn --fixed-fps 60
##
## Or open tests/phase2_test.tscn and press F6. Exit code 0 when every check passes.

const WORLD_SCENE := "res://scenes/world/world.tscn"
# Water features have no ground pad of their own.
const WATER_POINTS := ["mirror_lake", "river_spring", "creek_spring", "highfall", "willow_falls", "river_fishing",
	"outflow_cascade", "willow_isle", "fishing_pier", "lakeside_landing", "spawn"]
const GRADE_LIMITS := {"Village street": 0.03, "Main road": 0.08, "Lane": 0.10, "Footpath": 0.15, "Mountain trail": 0.30}

var _passed: int = 0
var _failed: int = 0
var _regions: Array[String] = []
var _notifications: Array[String] = []
var world: WorldManager
var player: PlayerController
var terrain: HeightmapTerrain


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.region_changed.connect(func(id: String, _name: String) -> void: _regions.append(id))
	EventBus.notification_requested.connect(func(title: String, _m: String) -> void: _notifications.append(title))
	_run.call_deferred()


func _run() -> void:
	print("--- Haven Valley Phase 2A test (Godot %s) ---" % Engine.get_version_info().string)
	world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	add_child(world)
	await _physics_frames(10)
	player = world.get_player()
	terrain = world.get_terrain()
	var layout := world.layout

	# Terrain matches the blueprint
	_check("terrain built (64 tiles + collision)", terrain.get_child_count() == 65, str(terrain.get_child_count()))
	var worst := 0.0
	var worst_id := ""
	for landmark: Dictionary in layout.get_landmarks():
		if landmark["id"] in WATER_POINTS:
			continue
		var p := WorldLayout.to_vec3(landmark["position"])
		var error := absf(terrain.get_height(p.x, p.z) - p.y)
		if error > worst:
			worst = error
			worst_id = landmark["id"]
	_check("every landmark sits at its blueprint height (±0.3 m)", worst <= 0.3, "%s off by %.2f m" % [worst_id, worst])
	_check("Mirror Lake bed is 8 m deep in the middle", absf(terrain.get_height(360, 80) + 8.0) < 0.3)
	_check("lake has a wading shelf near the shore", absf(terrain.get_height(360 + 110 * 0.95, 80) + 1.2) < 0.4, "%.2f" % terrain.get_height(360 + 104.5, 80))

	# Road grades: every 10 m stretch within the class limit (+1% for the 1 m grid), no 2 m step over 1.5x.
	var bridges: Array = []
	for bridge: Dictionary in layout.data.get("bridges", []):
		bridges.append(Vector2(bridge["position"][0], bridge["position"][2]))
	var over := PackedStringArray()
	for road: Dictionary in layout.data.get("roads", []):
		var limit: float = GRADE_LIMITS[road["class"]]
		var g := _grades(road["points_xz"], bridges)
		if g.x > limit + 0.01 or g.y > limit * 1.5 + 0.01:
			over.append("%s %.0f%%/%.0f%% (limit %.0f%%)" % [road["id"], g.x * 100, g.y * 100, limit * 100])
	_check("every road is within its grade limit", over.is_empty(), ", ".join(over))

	# Town Hall tower visible
	var tower_top := Vector3(0, 10 + 33.0, -24 - 4.5)
	for spot: Array in [["farm yard", Vector2(-150, 170)], ["Lakeside Landing", Vector2(245, 88)], ["trailhead", Vector2(-10, -244)]]:
		var eye := world.ground_at(spot[1].x, spot[1].y) + Vector3.UP * 1.7
		_check("Town Hall tower visible from the %s" % spot[0], _can_see(eye, tower_top), str(eye))

	# Walk from the farmhouse to the Town Hall along the Farm Road
	var farm_route := [Vector2(-140, 175), Vector2(-110, 125), Vector2(-70, 68), Vector2(-22, 26), Vector2(0, 12), Vector2(0, -12)]
	player.teleport(world.ground_at(-152, 176) + Vector3.UP * 0.05, Vector3(-140, 8, 175))
	await _physics_frames(5)
	var run_time := await _walk(farm_route, true, 90.0)
	_check("run farmhouse → Town Hall in about 45 s", run_time > 0.0 and run_time < 55.0, "%.1f s" % run_time)

	# Walk the North Road switchbacks from the trailhead to the mine
	var north_road: Array = []
	for road: Dictionary in layout.data.get("roads", []):
		if road["id"] == "R7":
			for p: Array in road["points_xz"]:
				if p[1] <= -250.0:
					north_road.append(Vector2(p[0], p[1]))
	player.teleport(world.ground_at(-10, -248) + Vector3.UP * 0.05, Vector3(-20, 20, -260))
	await _physics_frames(5)
	var climb := await _walk(north_road, false, 200.0)
	_check("walk up the North Road switchbacks to the Old Copper Mine", climb > 0.0, "%.1f s" % climb)
	_check("arrive at the mine entrance height (50 m)", absf(player.global_position.y - 50.0) < 1.5, str(player.global_position))

	# Cross the Forest Bridge over Willow Creek on the West Road
	var bridge_route := [Vector2(-190, -5), Vector2(-226, -15), Vector2(-265, -18)]
	player.teleport(world.ground_at(-180, -3) + Vector3.UP * 0.05, Vector3(-226, 8, -15))
	await _physics_frames(5)
	var lowest := [INF]
	var crossed := await _walk(bridge_route, false, 40.0, lowest)
	var creek_surface := 8.5  # creek surface near the bridge is about 7 m; bank tops are higher
	_check("walk across the Forest Bridge", crossed > 0.0, "%.1f s" % crossed)
	_check("never drop into the creek while crossing", lowest[0] > creek_surface, "lowest feet height %.2f" % lowest[0])

	# Regions
	_regions.clear()
	player.teleport(world.ground_at(-400, 0) + Vector3.UP * 0.05, Vector3(-400, 20, -100))
	await _physics_frames(3)
	_check("entering Westwood reports the forest region", _regions.has("forest"), str(_regions))
	player.teleport(world.ground_at(0, 400) + Vector3.UP * 0.05, Vector3(0, 5, 500))
	await _physics_frames(3)
	_check("entering the south reports the meadow region", _regions.has("meadow"), str(_regions))

	# Deep water returns the player to dry ground
	player.teleport(world.ground_at(-120, 300) + Vector3.UP * 0.05, Vector3(0, 5, 300))
	await _physics_frames(40)
	_notifications.clear()
	player.teleport(Vector3(360, 0.5, 80), Vector3(360, 0, 0))
	await _physics_frames(120)
	_check("walking into deep lake water returns the player to land", player.global_position.y > 0.0, str(player.global_position))
	_check("…with a message", _notifications.has("The water is too deep"), str(_notifications))

	# Water
	_check("river, creek, outflow and lake surfaces built", world.get_node("Water").get_child_count() == 4)

	print("--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Grades along a road polyline on the terrain, sampled every 1 m: the steepest 10 m stretch (what the
## player feels) and the steepest 2 m step. Water crossings (bridges carry the road) and the first and
## last 4 m (where roads meet pads) are skipped.
func _grades(points: Array, bridges: Array) -> Vector2:
	var samples: Array[Vector3] = []
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var steps := maxi(1, int(round(a.distance_to(b))))
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			samples.append(Vector3(p.x, terrain.get_height(p.x, p.y), p.y))
	var near_bridge: Array[bool] = []
	for p in samples:
		var close := false
		for b: Vector2 in bridges:
			if Vector2(p.x, p.z).distance_to(b) < 14.0:
				close = true
		near_bridge.append(close)
	var g10 := 0.0
	var g2 := 0.0
	for k in range(4, samples.size() - 14):
		if near_bridge.slice(k, k + 11).has(true):
			continue
		g10 = maxf(g10, absf(samples[k + 10].y - samples[k].y) / 10.0)
	for k in range(4, samples.size() - 6):
		if near_bridge.slice(k, k + 3).has(true):
			continue
		g2 = maxf(g2, absf(samples[k + 2].y - samples[k].y) / 2.0)
	return Vector2(g10, g2)


func _can_see(from: Vector3, to: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	# The ray may end on the tower itself.
	return (hit["position"] as Vector3).distance_to(to) < 6.0


## Drive the player along waypoints by turning the camera and holding forward. Returns seconds taken,
## or -1 on timeout. lowest[0] is updated with the lowest feet height seen.
func _walk(route: Array, run: bool, timeout: float, lowest: Array = [INF]) -> float:
	var rig := player.get_node("CameraRig") as PlayerCameraRig
	var elapsed := 0.0
	var index := 0
	Input.action_press("move_forward")
	if run:
		Input.action_press("run")
	while index < route.size() and elapsed < timeout:
		var target: Vector2 = route[index]
		var to := target - Vector2(player.global_position.x, player.global_position.z)
		if to.length() < 1.5:
			index += 1
			continue
		rig.set_yaw(atan2(-to.x, -to.y))
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		lowest[0] = minf(lowest[0], player.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("run")
	await _physics_frames(30)
	return elapsed if index >= route.size() else -1.0


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
