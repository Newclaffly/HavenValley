extends SceneTree
## Converts the raw heightmap from generate_terrain.py into Godot resources.
##
## Run from the project folder after generate_terrain.py:
##   godot --headless --path . -s res://tools/terrain/build_terrain_resources.gd
##
## Writes res://resources/world/terrain/heightmap.res (Image, 32-bit float, 1025 x 1025, metres) for the
## game, and heightmap.exr for importing into Terrain3D or Blender.

const SIZE := 1025
const RAW_PATH := "res://tools/terrain/out/heightmap_1025.f32"
const RES_PATH := "res://resources/world/terrain/heightmap.res"
const EXR_PATH := "res://resources/world/terrain/heightmap.exr"


func _init() -> void:
	var bytes := FileAccess.get_file_as_bytes(RAW_PATH)
	if bytes.size() != SIZE * SIZE * 4:
		push_error("Expected %d bytes in %s, found %d. Run generate_terrain.py first." % [SIZE * SIZE * 4, RAW_PATH, bytes.size()])
		quit(1)
		return
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, bytes)
	var error := ResourceSaver.save(image, RES_PATH, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not save %s (error %d)" % [RES_PATH, error])
		quit(1)
		return
	error = image.save_exr(ProjectSettings.globalize_path(EXR_PATH), true)
	if error != OK:
		push_error("Could not save %s (error %d)" % [EXR_PATH, error])
	print("Heightmap saved: %s and %s" % [RES_PATH, EXR_PATH])
	quit()
