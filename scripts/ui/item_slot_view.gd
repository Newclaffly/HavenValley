class_name ItemSlotView
extends Button
## One inventory slot on screen: item icon, stack count, optional hotbar key number.
## Built in code by Hotbar and InventoryPanel.

const SIZE := Vector2(76, 76)

var slot: int = -1

var _icon: TextureRect
var _count: Label
var _key: Label
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _style_marked: StyleBoxFlat


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	# Round cream buttons with the dark brown outline used by the art; gold ring when selected.
	_style_normal = _make_style(Color("fffaf0"), Color("3d2a20"), 3)
	_style_selected = _make_style(Color("fff3d6"), Color("f2b93a"), 6)
	_style_marked = _make_style(Color("e8f6d6"), Color("6fb36a"), 6)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, _style_normal)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = Label.new()
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -40
	_count.offset_top = -24
	_count.offset_right = -6
	_count.offset_bottom = 2
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 18)
	_count.add_theme_constant_override("outline_size", 6)
	_count.add_theme_color_override("font_color", Color("3d2a20"))
	_count.add_theme_color_override("font_outline_color", Color("fffaf0"))
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_key = Label.new()
	_key.position = Vector2(10, 4)
	_key.add_theme_font_size_override("font_size", 14)
	_key.add_theme_color_override("font_color", Color("8a6a50"))
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key)


func show_item(item: ItemData, count: int) -> void:
	_icon.texture = item.icon if item else null
	_count.text = str(count) if item and count > 1 else ""
	tooltip_text = "%s\n%s" % [item.display_name, item.description] if item else ""


func set_key_label(text: String) -> void:
	_key.text = text


## selected = current hotbar slot, marked = picked up in the inventory screen.
func set_highlight(selected: bool, marked: bool = false) -> void:
	var style := _style_marked if marked else (_style_selected if selected else _style_normal)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, style)


func get_count_text() -> String:
	return _count.text


func get_icon() -> Texture2D:
	return _icon.texture


func _make_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(int(SIZE.x / 2))
	style.shadow_color = Color(0.35, 0.18, 0.12, 0.25)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 3)
	return style
