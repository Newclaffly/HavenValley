class_name ForageSpot
extends Interactable
## Something picked by hand with E: berries on a bush, a mushroom cluster, wildflowers.
##
## Lives in the simulation (map pixels); `sprite` is its picture in the isometric view. Once picked
## it shows `picked_art` (or hides) until WorldState says it has grown back (HarvestSystem restores it).

const ID_PREFIX := "forage:"

@export var item: ItemData
@export var count: int = 1
## Permanent id, for example "forage:120_88".
@export var forage_id: String = ""
@export var regrow_seconds: float = 600.0

var sprite: Sprite2D
var full_art: String = ""
var picked_art: String = ""


func _ready() -> void:
	if item:
		prompt = "Pick %s" % item.display_name


func is_picked() -> bool:
	return not enabled


func set_picked(picked: bool) -> void:
	enabled = not picked
	if sprite == null:
		return
	if picked and picked_art == "":
		sprite.visible = false
		return
	sprite.visible = true
	var art := picked_art if picked else full_art
	sprite.texture = load(ArtLibrary.ART_DIR.path_join(art + ".png"))
	sprite.offset = -ArtLibrary.anchor(art)


func _on_interact(interactor: Node) -> void:
	var inventory := interactor.get_node_or_null("Inventory") as Inventory if interactor else null
	if inventory == null or item == null:
		return
	if not inventory.can_add(item, count):
		EventBus.notification_requested.emit("Bag full", "Make room to pick up %s." % item.display_name)
		return
	inventory.add_item(item, count)
	set_picked(true)
	WorldState.mark_harvested(forage_id, regrow_seconds)
