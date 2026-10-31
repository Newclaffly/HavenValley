class_name ArtLibrary
extends RefCounted
## The generated isometric art in res://assets/art/ (see tools/art/iso_art.py).
##
## Each image has an anchor in assets/art/manifest.json: the pixel where the object touches the
## ground. Images are drawn at 2x, so sprites use scale 0.5.

const ART_DIR := "res://assets/art"
const MANIFEST := "res://assets/art/manifest.json"
const SCALE := 0.5

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var file := FileAccess.open(MANIFEST, FileAccess.READ)
		if file:
			_manifest = JSON.parse_string(file.get_as_text())
	return _manifest


static func has_art(art_name: String) -> bool:
	return manifest().has(art_name) and ResourceLoader.exists(ART_DIR.path_join(art_name + ".png"))


## Anchor pixel of an image (where it touches the ground), in image pixels.
static func anchor(art_name: String) -> Vector2:
	var a: Array = manifest().get(art_name, {}).get("anchor", [0, 0])
	return Vector2(a[0], a[1])


## A Sprite2D whose origin is the object's ground point. Returns null if the art is missing.
static func make_sprite(art_name: String) -> Sprite2D:
	if not has_art(art_name):
		push_warning("ArtLibrary: no art named %s" % art_name)
		return null
	var sprite := Sprite2D.new()
	sprite.name = art_name
	sprite.texture = load(ART_DIR.path_join(art_name + ".png"))
	sprite.centered = false
	sprite.offset = -anchor(art_name)
	sprite.scale = Vector2.ONE * SCALE
	return sprite
