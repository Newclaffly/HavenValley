extends Node
## Automated check for Phase 3A: items, inventory, hotbar, bag screen, chopping, mining, foraging.
##
##   godot --headless --path . res://tests/p3a_test.tscn
##
## Exit code 0 when every check passes.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _passed: int = 0
var _failed: int = 0
var world: WorldManager
var player: PlayerController
var inventory: Inventory
var tools: ToolUser
var harvest: HarvestSystem


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("--- Haven Valley Phase 3A test (Godot %s) ---" % Engine.get_version_info().string)
	var wood := ItemRegistry.get_item(&"wood")
	var stone := ItemRegistry.get_item(&"stone")
	var axe := ItemRegistry.get_item(&"axe")
	var pickaxe := ItemRegistry.get_item(&"pickaxe")
	_check("item registry loads all 7 items", ItemRegistry.all_ids().size() == 7, str(ItemRegistry.all_ids()))
	_check("every item has an icon and ground art", ItemRegistry.all_ids().all(func(id: StringName) -> bool:
		var it := ItemRegistry.get_item(id)
		return it.icon != null and ArtLibrary.has_art(it.world_art)))

	# Inventory rules (standalone)
	var bag := Inventory.new()
	bag.size = 4
	bag.hotbar_size = 2
	add_child(bag)
	_check("adds a stack", bag.add_item(wood, 150) == 0 and bag.get_count(0) == 99 and bag.get_count(1) == 51)
	_check("returns what does not fit", bag.add_item(wood, 300) == 300 - (99 * 4 - 150), str(bag.count_of(wood)))
	_check("tools do not stack", (func() -> bool:
		var b := Inventory.new(); b.size = 3; add_child(b)
		b.add_item(axe, 2)
		var ok := b.get_count(0) == 1 and b.get_count(1) == 1
		b.queue_free()
		return ok).call())
	_check("remove takes from the last stacks first", bag.remove_item(wood, 10) and bag.get_count(3) == 89)
	_check("remove refuses when there are not enough", not bag.remove_item(wood, 10000) and bag.count_of(wood) == 386)
	bag.clear()
	bag.add_item(wood, 5)
	bag.add_item(stone, 3)
	bag.move_slot(0, 1)
	_check("moving onto another item swaps", bag.get_item(0) == stone and bag.get_item(1) == wood)
	bag.add_item(wood, 2)
	bag.move_slot(2, 1)
	_check("moving onto the same item merges", bag.get_count(1) == 7 and bag.is_empty_slot(2), "%d" % bag.get_count(1))
	var saved := bag.to_dict()
	bag.clear()
	bag.from_dict(saved)
	_check("inventory saves and loads", bag.get_count(1) == 7 and bag.get_item(0) == stone)
	bag.queue_free()

	# The world with the player's real inventory
	world = (load(WORLD_SCENE) as PackedScene).instantiate() as WorldManager
	add_child(world)
	await _frames(3)
	player = world.get_player()
	inventory = player.get_node("Inventory")
	tools = player.get_node("ToolUser")
	harvest = world.get_node("HarvestSystem")
	var hud := world.get_node("HUD")
	_check("new game starts with an axe and a pickaxe", inventory.has(axe) and inventory.has(pickaxe))
	_check("hotbar shows 8 slots with the axe in slot 1", hud.hotbar.slots.size() == 8 and hud.hotbar.slots[0].get_icon() == axe.icon)
	await _press("hotbar_2")
	await _frames(3)
	_check("key 2 selects hotbar slot 2", inventory.selected == 1 and inventory.get_selected_item() == pickaxe, "selected %d item %s / slot1 %s" % [inventory.selected, inventory.get_selected_item(), inventory.get_item(1)])
	await _press("hotbar_1")
	await _frames(3)

	# Chop a pine
	var tree_id := _first_harvestable("tree_pine")
	var tree: Dictionary = world.objects.harvestables[tree_id]
	_stand_facing(tree["pos"])
	await _frames(4)
	_check("standing at a tree with the axe offers Chop", tools.current_target == tree_id, tools.current_target + " / " + tree_id)
	var hits := 0
	var left := 99
	while left > 0 and hits < 10:
		left = tools.use_selected()
		hits += 1
		await _seconds(tools.swing_cooldown + 0.02)
	_check("a pine falls after 4 hits", hits == 4 and left == 0, "%d hits, left %d" % [hits, left])
	_check("the tree becomes a stump", tree["hidden"] and (tree["sprite"] as Sprite2D).texture.resource_path.ends_with("stump_pine.png") or (tree["sprite"] as Sprite2D).texture.resource_path.ends_with("stump.png"))
	_check("the stump no longer blocks", (tree["shape"] as CollisionShape2D).disabled)
	_check("the felled tree is remembered", WorldState.is_harvested(tree_id))
	var drops := get_tree().get_nodes_in_group("item_pickups").size()
	_check("wood drops on the ground", drops >= 3, str(drops))
	await _seconds(1.5)
	_check("dropped wood flies into the bag", inventory.count_of(wood) >= 3 and get_tree().get_nodes_in_group("item_pickups").is_empty(), "%d wood" % inventory.count_of(wood))

	# Mine a rock with the wrong then the right tool
	var rock_id := _first_harvestable("rock_small")
	var rock: Dictionary = world.objects.harvestables[rock_id]
	_stand_facing(rock["pos"])
	await _frames(4)
	_check("the axe does not target rocks", tools.current_target == "")
	inventory.select(1)
	await _frames(2)
	_check("the pickaxe targets the rock", tools.current_target == rock_id)
	for i in 2:
		tools.use_selected()
		await _seconds(tools.swing_cooldown + 0.02)
	await _seconds(1.5)
	_check("a small rock breaks after 2 hits and gives stone", rock["hidden"] and inventory.count_of(stone) >= 1, "%d stone" % inventory.count_of(stone))
	_check("a broken rock disappears", not (rock["sprite"] as Sprite2D).visible)

	# Nothing selected: no swing
	inventory.select(5)
	_check("an empty hand does not hit", tools.use_selected() == -1)
	inventory.select(0)

	# Foraging
	var spot: ForageSpot = null
	for s: ForageSpot in world.objects.forage_spots.values():
		if s.item.id == &"mushroom":
			spot = s
			break
	_check("mushrooms grow in the forest", spot != null and world.objects.counts.get("forage_mushrooms", 0) >= 30, str(world.objects.counts.get("forage_mushrooms", 0)))
	_check("berry bushes and wildflowers can be picked", world.objects.forage_spots.values().any(func(s: ForageSpot) -> bool: return s.item.id == &"wild_berries")
		and world.objects.forage_spots.values().any(func(s: ForageSpot) -> bool: return s.item.id == &"wildflower"))
	player.input_transform = Transform2D.IDENTITY
	player.teleport(spot.position + Vector2(0, 12), Vector2.UP)
	await _frames(5)
	await _press("interact")
	await _frames(3)
	_check("E picks the mushrooms", inventory.count_of(ItemRegistry.get_item(&"mushroom")) == 1 and spot.is_picked())
	_check("picked mushrooms disappear", not spot.sprite.visible)
	player.input_transform = WorldLayout.screen_to_ground()

	# Regrowth (shortened for the test)
	harvest.tree_regrow_seconds = 0.0
	WorldState.mark_harvested(tree_id, 0.5)
	WorldState.mark_harvested(spot.forage_id, 0.5)
	player.teleport(player.global_position + Vector2(400, 0), Vector2.DOWN)
	await _seconds(2.5)
	_check("the tree grows back", not tree["hidden"] and not (tree["shape"] as CollisionShape2D).disabled)
	_check("the mushrooms grow back", not spot.is_picked() and spot.sprite.visible)

	# Bag screen
	await _press("inventory")
	await _frames(2)
	_check("Tab opens the bag", hud.inventory_panel.is_open() and not player.input_enabled)
	var panel: InventoryPanel = hud.inventory_panel
	var before := inventory.get_item(0)
	panel._on_slot_pressed(0)
	panel._on_slot_pressed(10)
	_check("click-click moves a stack in the bag", inventory.get_item(10) == before and inventory.is_empty_slot(0) or inventory.get_item(0) != before)
	panel._on_slot_pressed(10)
	panel._on_slot_pressed(0)
	await _press("inventory")
	await _frames(2)
	_check("Tab closes the bag and gives control back", not hud.inventory_panel.is_open() and player.input_enabled)

	# Full bag: pickups wait on the ground
	inventory.remove_item(stone, inventory.count_of(stone))
	var filler := ItemRegistry.get_item(&"wildflower")
	while inventory.add_item(filler, 99) == 0:
		pass
	var pickup := harvest.spawn_pickup(stone, 1, player.global_position + Vector2(4, 0))
	await _seconds(1.0)
	_check("a full bag leaves pickups on the ground", is_instance_valid(pickup) and not pickup.collected)

	print("--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _first_harvestable(art: String) -> String:
	var spawn := player.global_position
	var best := ""
	var best_d := INF
	for id: String in world.objects.harvestables:
		var info: Dictionary = world.objects.harvestables[id]
		if info["art"] == art and not info["hidden"]:
			var d := spawn.distance_to(info["pos"])
			if d < best_d:
				best_d = d
				best = id
	return best


## Put the player beside a point, facing it (south of it, looking north on the map).
func _stand_facing(target: Vector2) -> void:
	player.input_transform = Transform2D.IDENTITY
	player.teleport(target + Vector2(0, 8), Vector2.UP)
	player.input_transform = Transform2D.IDENTITY


## Press and release an action, then wait until the input has been processed (input is flushed
## once per rendered frame, which can be several physics frames).
func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
	for i in 2:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  [%s]" % [label, detail])
