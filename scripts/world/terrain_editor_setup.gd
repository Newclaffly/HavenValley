@tool
extends Node3D
## Root script of scenes/world/terrain_editor.tscn, the scene for sculpting the terrain with Terrain3D.
##
## Gives the Terrain3D material the Haven Valley ground maps each time the scene opens (Terrain3D does
## not keep texture shader parameters in the saved scene).

@export var control_map: Texture2D = preload("res://resources/world/terrain/control.png")
@export var zone_map: Texture2D = preload("res://resources/world/terrain/zones.png")


func _ready() -> void:
	var terrain := get_node_or_null("Terrain3D")
	if terrain == null:
		return
	var material: Object = terrain.get("material")
	if material:
		# Terrain3D turns on its checkerboard view when no textures are painted; our shader colours the ground.
		material.set("show_checkered", false)
		material.call("set_shader_param", "control_map", control_map)
		material.call("set_shader_param", "zone_map", zone_map)
