class_name CharacterSprite
extends AnimatedSprite2D
## A 4-direction character drawn from one sprite sheet.
##
## Sheet layout (the Ninja Adventure "Walk.png" layout, also used by the placeholder):
## one column per direction in DIRECTIONS order, one row per walk frame, frame_size pixels each.
## Builds animations "idle_down", "walk_down", … at runtime, so swapping the character is just
## assigning another sheet.

const DIRECTIONS := ["down", "up", "left", "right"]

@export var sheet: Texture2D:
	set(value):
		sheet = value
		if is_node_ready():
			rebuild()
@export var frame_size: Vector2i = Vector2i(16, 16)
@export var walk_frames: int = 4
@export var walk_fps: float = 8.0

var facing: String = "down"


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if sheet == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for column in DIRECTIONS.size():
		var direction: String = DIRECTIONS[column]
		var idle := "idle_" + direction
		var walk := "walk_" + direction
		frames.add_animation(idle)
		frames.add_animation(walk)
		frames.set_animation_speed(walk, walk_fps)
		frames.add_frame(idle, _frame(column, 0))
		for row in walk_frames:
			frames.add_frame(walk, _frame(column, row))
	sprite_frames = frames
	play("idle_" + facing)


## Show walking (or standing) toward a direction: "down", "up", "left" or "right".
## speed_scale lets running play the walk faster.
func show_motion(direction: String, moving: bool, speed: float = 1.0) -> void:
	facing = direction
	var anim := ("walk_" if moving else "idle_") + direction
	if animation != anim:
		play(anim)
	speed_scale = speed


func _frame(column: int, row: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(column * frame_size.x, row * frame_size.y), frame_size)
	return atlas
