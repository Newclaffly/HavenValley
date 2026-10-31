class_name ItemPickup
extends Node2D
## An item lying on the ground (drawn in the isometric view). After a short pop it waits; when the
## player comes near it flies to them and goes into their inventory. If the bag is full it waits.
##
## `map_position` is in simulation (map) pixels; the node's own position is the view position.

@export var item: ItemData
@export var count: int = 1
## Map pixels at which the pickup starts flying to the player, and is collected.
@export var attract_radius: float = 26.0
@export var collect_radius: float = 3.0
@export var fly_speed: float = 70.0  # map pixels per second
@export var settle_time: float = 0.45

var map_position: Vector2
var collected: bool = false

var _age: float = 0.0
var _sprite: Sprite2D
var _pop: float = 0.0


func _ready() -> void:
	add_to_group("item_pickups")
	if item and ArtLibrary.has_art(item.world_art):
		_sprite = ArtLibrary.make_sprite(item.world_art)
		add_child(_sprite)
	position = WorldLayout.to_view(map_position)
	_pop = 1.0


func _physics_process(delta: float) -> void:
	_age += delta
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	var inventory := get_tree().get_first_node_in_group("player_inventory") as Inventory
	if player and inventory and not collected and _age > settle_time and inventory.can_add(item, count):
		var target := player.global_position
		if map_position.distance_to(target) < attract_radius:
			map_position = map_position.move_toward(target, fly_speed * delta)
			if map_position.distance_to(target) < collect_radius:
				var left := inventory.add_item(item, count)
				if left == 0:
					collected = true
					queue_free()
				else:
					count = left
	position = WorldLayout.to_view(map_position)
	if _sprite:
		# A little hop when dropped, then a gentle bob.
		_pop = maxf(0.0, _pop - delta * 2.5)
		_sprite.position.y = -sin(_pop * PI) * 40.0 - (sin(_age * 3.0) + 1.0) * 3.0
