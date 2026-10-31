class_name PlayerCameraRig
extends Node3D
## Orbit camera that follows its parent (the player).
##
## The mouse turns it while the cursor is captured, the mouse wheel zooms, and a SpringArm3D
## pulls the camera in front of walls so it never looks through them.
## Expected children: Pitch (Node3D) → SpringArm3D → Camera3D.
##
## The rig is top_level and follows the player's interpolated transform every rendered frame,
## so the view stays smooth at any monitor refresh rate while physics runs at 60 Hz.

@export_group("Follow")
## Height of the orbit centre above the player's feet, in metres.
@export var height_offset: float = 1.5

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.0025
@export var invert_y: bool = false
@export_range(-89.0, 0.0) var min_pitch_degrees: float = -70.0
@export_range(0.0, 89.0) var max_pitch_degrees: float = 40.0

@export_group("Zoom")
@export var min_distance: float = 2.0
@export var max_distance: float = 8.0
@export var zoom_step: float = 0.5
@export var zoom_smoothing: float = 10.0

var _target: Node3D
var _yaw: float = 0.0
var _pitch_angle: float = deg_to_rad(-18.0)
var _distance_target: float = 4.5

@onready var _pitch: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	# The rig is moved manually from the interpolated target, so it must not be interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_parent() as Node3D
	if _target is CollisionObject3D:
		_arm.add_excluded_object((_target as CollisionObject3D).get_rid())
	_distance_target = _arm.spring_length
	_apply_rotation()
	snap_to_target()
	_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		var vertical := motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		_pitch_angle = clampf(_pitch_angle - vertical, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
		_apply_rotation()
	elif event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance_target = maxf(min_distance, _distance_target - zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance_target = minf(max_distance, _distance_target + zoom_step)
			MOUSE_BUTTON_LEFT:
				# Clicking back into the game window re-captures the cursor.
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_follow_target()
	_arm.spring_length = lerpf(_arm.spring_length, _distance_target, 1.0 - exp(-zoom_smoothing * delta))


## Rotation around the vertical axis only. Movement uses this so looking up or down never slows the player.
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


func set_yaw(yaw: float) -> void:
	_yaw = yaw
	_apply_rotation()


## Jump straight to the target without smoothing (after spawning or teleporting).
func snap_to_target() -> void:
	_follow_target()


func get_camera() -> Camera3D:
	return _camera


func _follow_target() -> void:
	if _target:
		global_position = _target.get_global_transform_interpolated().origin + Vector3.UP * height_offset


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch.rotation = Vector3(_pitch_angle, 0.0, 0.0)
