extends SceneTree
## Imports the generated heightmap into Terrain3D data files.
##
## Run after generate_terrain.py + build_terrain_resources.gd, from the project folder:
##   godot --headless --path . -s res://tools/terrain/import_to_terrain3d.gd
##
## Writes res://resources/world/terrain/terrain3d/ (one file per 256 m region). This REPLACES any
## sculpting done in the Terrain3D editor, so export hand-made changes first with
## export_from_terrain3d.gd if you want to keep them.

const HEIGHTMAP_PATH := "res://resources/world/terrain/heightmap.exr"
const DATA_DIR := "res://resources/world/terrain/terrain3d"
const REGION_SIZE := 256
const ORIGIN := Vector3(-512, 0, -512)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		push_error("Terrain3D is not installed or not enabled in this project.")
		quit(1)
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(HEIGHTMAP_PATH))
	if image == null or image.is_empty():
		push_error("Could not read %s" % HEIGHTMAP_PATH)
		quit(1)
		return
	image.convert(Image.FORMAT_RF)

	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.set("region_size", REGION_SIZE)
	root.add_child(terrain)
	await process_frame
	var data: Object = terrain.get("data")
	data.call("import_images", [image, null, null], ORIGIN, 0.0, 1.0)

	var dir := ProjectSettings.globalize_path(DATA_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("terrain3d") and file.ends_with(".res"):
			DirAccess.remove_absolute(dir.path_join(file))
	data.call("save_directory", DATA_DIR)
	print("Imported %s into %s: %d regions" % [HEIGHTMAP_PATH, DATA_DIR, data.call("get_region_count")])
	quit()
