class_name PlayerController
extends CharacterBody3D
## Third-person movement: camera-relative walking and running, jumping, and turning to face
## the direction of travel.
##
## Expected children: Model (Node3D, turns to face movement) and CameraRig (PlayerCameraRig).
## The body's origin is at the feet.

@export_group("Movement")
## Walking speed in m/s.
@export var walk_speed: float = 4.0
## Running speed in m/s while "run" (Shift) is held.
@export var run_speed: float = 7.0
## How fast the player reaches the target speed on the ground (m/s²).
@export var acceleration: float = 30.0
## How fast the player stops on the ground when no key is held (m/s²).
@export var deceleration: float = 40.0
## Steering in the air (m/s²). Lower than ground acceleration.
@export var air_acceleration: float = 8.0
## How quickly the model turns toward the movement direction.
@export var turn_speed: float = 12.0

@export_group("Jump")
## Jump apex height in metres.
@export var jump_height: float = 1.2
## Seconds after leaving a ledge during which a jump still counts.
@export var coyote_time: float = 0.12
## Seconds a jump press is remembered before landing.
@export var jump_buffer_time: float = 0.12

## When false the player ignores movement input (used later for menus, dialogue, cutscenes).
var input_enabled: bool = true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

@onready var _model: Node3D = $Model
@onready var _camera_rig: PlayerCameraRig = $CameraRig


func _ready() -> void:
	add_to_group("player")
	floor_max_angle = deg_to_rad(40.0)
	floor_snap_length = 0.3


func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	var wants_run := false
	var wants_jump := false
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wants_run = Input.is_action_pressed("run")
		wants_jump = Input.is_action_just_pressed("jump")

	# Movement is relative to where the camera looks, flattened onto the ground.
	var direction := _camera_rig.get_yaw_basis() * Vector3(input_dir.x, 0.0, input_dir.y)
	var target_velocity := direction * (run_speed if wants_run else walk_speed)

	var rate := air_acceleration
	if is_on_floor():
		rate = acceleration if direction != Vector3.ZERO else deceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y -= _gravity * delta

	_jump_buffer_timer = jump_buffer_time if wants_jump else _jump_buffer_timer - delta
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = sqrt(2.0 * _gravity * jump_height)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	move_and_slide()

	if direction.length_squared() > 0.0001:
		# The model looks down its -Z axis.
		var target_yaw := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


## Horizontal speed in m/s, for animation and debug display.
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Place the player at a world position, facing a point. Used for spawning.
func teleport(position_world: Vector3, look_at_point: Vector3) -> void:
	global_position = position_world
	velocity = Vector3.ZERO
	var to_target := look_at_point - position_world
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		var yaw := atan2(-to_target.x, -to_target.z)
		_model.rotation.y = yaw
		_camera_rig.set_yaw(yaw)
	reset_physics_interpolation()
	_camera_rig.snap_to_target()
