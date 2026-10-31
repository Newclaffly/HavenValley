class_name PlayerController
extends CharacterBody2D
## Top-down movement in 8 directions with 4-direction facing, walking and running.
##
## Expected children: Sprite (CharacterSprite), Facing (Node2D that points where the player faces;
## the InteractionDetector lives under it) and Camera (Camera2D).
## The body's origin is at the feet; speeds are in tiles per second (1 tile = 16 px).

@export_group("Movement")
@export var walk_tiles_per_second: float = 5.0
@export var run_tiles_per_second: float = 8.0
## How quickly the player reaches full speed, in tiles/s².
@export var acceleration: float = 60.0
@export var deceleration: float = 80.0

## Maps screen directions to ground directions. Identity for a top-down view; the isometric
## world sets it so W walks up the screen (north-west on the ground).
@export var input_transform: Transform2D = Transform2D.IDENTITY

## When false the player ignores movement input (menus, dialogue, cutscenes).
var input_enabled: bool = true
## Facing on screen as a unit vector (down = (0, 1)); the sprite shows this direction.
var facing: Vector2 = Vector2.DOWN

@onready var _sprite: CharacterSprite = $Sprite
@onready var _facing_node: Node2D = $Facing


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	var running := false
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		running = Input.is_action_pressed("run")
	var speed := (run_tiles_per_second if running else walk_tiles_per_second) * WorldLayout.TILE_PX
	var ground_input := input_transform.basis_xform(input)
	if ground_input.length_squared() > 0.0:
		ground_input = ground_input.normalized() * minf(input.length(), 1.0)
	var target := ground_input * speed
	var rate := (acceleration if input != Vector2.ZERO else deceleration) * WorldLayout.TILE_PX
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()

	if input.length_squared() > 0.01:
		# Face the stronger axis; ties keep the current facing so diagonals don't flicker.
		if absf(input.x) > absf(input.y) + 0.1:
			facing = Vector2(signf(input.x), 0)
		elif absf(input.y) > absf(input.x) + 0.1:
			facing = Vector2(0, signf(input.y))
		elif facing.dot(input) <= 0.0:
			facing = Vector2(signf(input.x), 0)
	_facing_node.rotation = ground_facing().angle() - PI * 0.5  # Facing's +Y points where the player looks
	var moving := velocity.length() > 4.0
	_sprite.show_motion(direction_name(), moving, 1.5 if running else 1.0)


## "down", "up", "left" or "right".
func direction_name() -> String:
	if facing.x < 0.0:
		return "left"
	if facing.x > 0.0:
		return "right"
	return "up" if facing.y < 0.0 else "down"


## Facing direction on the ground (unit vector), for reach and interaction.
func ground_facing() -> Vector2:
	return input_transform.basis_xform(facing).normalized()


func get_speed_tiles() -> float:
	return velocity.length() / WorldLayout.TILE_PX


## Place the player at a world position (pixels), facing a direction.
func teleport(position_px: Vector2, face: Vector2 = Vector2.DOWN) -> void:
	global_position = position_px
	velocity = Vector2.ZERO
	facing = face
	_facing_node.rotation = ground_facing().angle() - PI * 0.5
	reset_physics_interpolation()
	var camera := get_node_or_null("Camera") as Camera2D
	if camera:
		camera.reset_smoothing()
