extends SceneTree
## Copies the Terrain3D heights (including anything sculpted in the editor) back into
## heightmap.res and heightmap.exr, so the built-in fallback terrain and the tests match.
##
##   godot --headless --path . -s res://tools/terrain/export_from_terrain3d.gd

const DATA_DIR := "res://resources/world/terrain/terrain3d"
const RES_PATH := "res://resources/world/terrain/heightmap.res"
const EXR_PATH := "res://resources/world/terrain/heightmap.exr"
const SIZE := 1025
const ORIGIN := Vector2(-512, -512)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		push_error("Terrain3D is not installed or not enabled in this project.")
		quit(1)
		return
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.set("region_size", 256)
	root.add_child(terrain)
	await process_frame
	terrain.set("data_directory", DATA_DIR)
	await process_frame
	var data: Object = terrain.get("data")
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	var missing := 0
	for z in SIZE:
		for x in SIZE:
			var h: float = data.call("get_height", Vector3(ORIGIN.x + x, 0, ORIGIN.y + z))
			if is_nan(h):
				h = 0.0
				missing += 1
			heights[z * SIZE + x] = h
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())
	ResourceSaver.save(image, RES_PATH, ResourceSaver.FLAG_COMPRESS)
	image.save_exr(ProjectSettings.globalize_path(EXR_PATH), true)
	print("Exported Terrain3D heights to %s and %s (%d samples outside regions)" % [RES_PATH, EXR_PATH, missing])
	quit()
