extends Control

## Two-Wall Isometric Terrain Constructor
## Phase 1: UI Framework & Canvas Setup
## Phase 2: Multi-set file importer
## Phase 3: Per-set asset grid & click-to-paint

# ── References ───────────────────────────────────────────────
@onready var sub_viewport: SubViewport = %SubViewport
@onready var sub_viewport_container: SubViewportContainer = %SubViewportContainer
@onready var canvas_panel: PanelContainer = %CanvasPanel
@onready var canvas_bg_color: ColorPickerButton = %CanvasBgColorPicker
@onready var room_color_picker: ColorPickerButton = %RoomColorPicker
@onready var canvas_background: ColorRect = %CanvasBackground
@onready var floor_poly: Polygon2D = %FloorPolygon
@onready var wall_back_poly: Polygon2D = %WallBackPolygon
@onready var wall_left_poly: Polygon2D = %WallLeftPolygon
@onready var room_outline: Line2D = %RoomOutline
@onready var asset_drop_zone: Node2D = %AssetDropZone
@onready var add_assets_button: Button = %AddAssetsButton
@onready var asset_sections_container: VBoxContainer = %AssetSectionsContainer
@onready var main_vbox: VBoxContainer = %MainVBox

# ── Constants ────────────────────────────────────────────────
const ISO_WIDTH := 600.0
const ISO_HEIGHT := 300.0
const WALL_HEIGHT := 200.0
const COLOR_BG := Color(0.12, 0.11, 0.14)
const COLOR_ROOM := Color(0.55, 0.65, 0.85)

# ── State ────────────────────────────────────────────────────
var active_asset_index: int = -1
var active_asset_texture: AtlasTexture = null
var placed_sprites: Array = []
var _next_set_id: int = 0
var asset_sets: Array = []
var _set_count: int = 0

# ── Preview ──────────────────────────────────────────────────
var _preview_panel: PanelContainer
var _preview_tex: TextureRect

# ── Confirm dialog ───────────────────────────────────────────
var _confirm_dialog: ConfirmationDialog
var _pending_removal_id: int = -1


func _ready() -> void:
	_apply_bg_color(COLOR_BG)
	_apply_room_color(COLOR_ROOM)
	_draw_room()
	call_deferred("_fit_camera")
	canvas_bg_color.color_changed.connect(_apply_bg_color)
	room_color_picker.color_changed.connect(_apply_room_color)

	_setup_preview()
	_setup_confirm_dialog()
	_setup_collapsibles()
	add_assets_button.pressed.connect(_on_add_assets_pressed)
	sub_viewport_container.gui_input.connect(_on_canvas_gui_input)

	call_deferred("_auto_load_test_assets")


# ════════════════════════════════════════════════════════════
# Phase 1: Camera & Room
# ════════════════════════════════════════════════════════════

func _fit_camera() -> void:
	var vp_size := Vector2(sub_viewport.size)
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(800, 600)
	var room_w := ISO_WIDTH
	var room_h := ISO_HEIGHT + WALL_HEIGHT
	var zoom_x := vp_size.x * 0.8 / room_w
	var zoom_y := vp_size.y * 0.8 / room_h
	var zoom_val := clampf(minf(zoom_x, zoom_y), 0.3, 3.0)
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	cam.zoom = Vector2(zoom_val, zoom_val)
	cam.position = Vector2(0.0, -175.0)


func _draw_room() -> void:
	var hw := ISO_WIDTH / 2.0
	var hh := ISO_HEIGHT / 2.0
	var wh := WALL_HEIGHT
	floor_poly.polygon = PackedVector2Array([
		Vector2(0.0, -hh), Vector2(hw, 0.0), Vector2(0.0, hh), Vector2(-hw, 0.0)])
	wall_back_poly.polygon = PackedVector2Array([
		Vector2(0.0, -hh), Vector2(hw, 0.0),
		Vector2(hw, -hh - wh), Vector2(0.0, -hh - hh - wh)])
	wall_left_poly.polygon = PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(0.0, -hh),
		Vector2(0.0, -hh - hh - wh), Vector2(-hw, -hh - wh)])
	room_outline.clear_points()
	for p in [Vector2(-hw, 0.0), Vector2(0.0, -hh), Vector2(0.0, -hh - hh - wh),
			  Vector2(hw, -hh - wh), Vector2(hw, 0.0), Vector2(0.0, hh),
			  Vector2(-hw, 0.0)]:
		room_outline.add_point(p)


func _apply_bg_color(color: Color) -> void:
	var existing = canvas_panel.get_theme_stylebox("panel")
	var style: StyleBoxFlat
	if existing is StyleBoxFlat:
		style = existing.duplicate() as StyleBoxFlat
	else:
		style = StyleBoxFlat.new()
	style.bg_color = color
	canvas_panel.add_theme_stylebox_override("panel", style)


func _apply_room_color(color: Color) -> void:
	room_outline.default_color = color
	room_outline.width = 2.0
	var h := color.h
	var s := color.s
	var v := color.v
	floor_poly.color = Color.from_hsv(h, s * 0.55, v * 0.45)
	wall_back_poly.color = Color.from_hsv(h, s * 0.45, v * 0.35)
	wall_left_poly.color = Color.from_hsv(h, s * 0.35, v * 0.28)


# ════════════════════════════════════════════════════════════
# Collapsible Sections
# ════════════════════════════════════════════════════════════

func _setup_collapsibles() -> void:
	# Connect static section headers
	for section in _get_static_sections():
		_connect_section_toggle(section)


func _connect_section_toggle(section: Control) -> void:
	var btn: Button = section.get_node_or_null("HeaderButton")
	var content: Control = section.get_node_or_null("Content")
	if btn and content:
		var title := btn.text.replace("▼ ", "").replace("▶ ", "")
		btn.pressed.connect(_toggle_section.bind(btn, content, title))


func _toggle_section(btn: Button, content: Control, title: String) -> void:
	content.visible = !content.visible
	btn.text = ("▼ " if content.visible else "▶ ") + title


func _get_static_sections() -> Array:
	var result: Array = []
	for child in main_vbox.get_children():
		if child.name.ends_with("Section"):
			result.append(child)
	return result


# ════════════════════════════════════════════════════════════
# Confirm Dialog
# ════════════════════════════════════════════════════════════

func _setup_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Remove this asset set and all its assets from the canvas?"
	add_child(_confirm_dialog)
	_confirm_dialog.confirmed.connect(_on_confirm_removal)


func _on_confirm_removal() -> void:
	if _pending_removal_id >= 0:
		_remove_asset_set(_pending_removal_id)
		_pending_removal_id = -1


# ════════════════════════════════════════════════════════════
# Phase 2: Multi-Set Importer
# ════════════════════════════════════════════════════════════

func _on_add_assets_pressed() -> void:
	_next_set_id += 1
	_set_count += 1
	var set_id := _next_set_id

	var entry = {
		"id": set_id,
		"png_path": "",
		"json_path": "",
		"sheet_texture": null,
		"frames": [],
		"textures": [],
		"section": _create_asset_section(set_id, _set_count),
	}
	asset_sets.append(entry)
	asset_sections_container.add_child(entry["section"])


func _create_asset_section(set_id: int, number: int) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "AssetSet_%d" % set_id

	# Header button (collapsible)
	var btn := Button.new()
	btn.name = "HeaderButton"
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = "▼ Assets %d" % number
	btn.clip_text = true
	section.add_child(btn)

	# Content container
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(content)

	# Connect toggle
	btn.pressed.connect(_toggle_section.bind(btn, content, "Assets %d" % number))

	# PNG row
	var png_row := HBoxContainer.new()
	png_row.name = "PngRow"
	var png_label := Label.new()
	png_label.name = "PngLabel"
	png_label.text = "Load Sprite Sheet (.png)"
	png_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	png_label.clip_text = true
	png_row.add_child(png_label)
	var png_btn := Button.new()
	png_btn.name = "PngLoadBtn"
	png_btn.text = "..."
	png_btn.custom_minimum_size = Vector2(24, 0)
	png_btn.pressed.connect(_on_set_png_pressed.bind(set_id))
	png_row.add_child(png_btn)
	var png_trash := Button.new()
	png_trash.name = "PngTrash"
	png_trash.text = "🗑"
	png_trash.custom_minimum_size = Vector2(24, 0)
	png_trash.visible = false
	png_trash.pressed.connect(_on_set_remove_pressed.bind(set_id))
	png_row.add_child(png_trash)
	content.add_child(png_row)

	# JSON row
	var json_row := HBoxContainer.new()
	json_row.name = "JsonRow"
	var json_label := Label.new()
	json_label.name = "JsonLabel"
	json_label.text = "Load JSON Data (.json)"
	json_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	json_label.clip_text = true
	json_row.add_child(json_label)
	var json_btn := Button.new()
	json_btn.name = "JsonLoadBtn"
	json_btn.text = "..."
	json_btn.custom_minimum_size = Vector2(24, 0)
	json_btn.pressed.connect(_on_set_json_pressed.bind(set_id))
	json_row.add_child(json_btn)
	var json_trash := Button.new()
	json_trash.name = "JsonTrash"
	json_trash.text = "🗑"
	json_trash.custom_minimum_size = Vector2(24, 0)
	json_trash.visible = false
	json_trash.pressed.connect(_on_set_remove_pressed.bind(set_id))
	json_row.add_child(json_trash)
	content.add_child(json_row)

	# Thumbnails
	var thumbs := HFlowContainer.new()
	thumbs.name = "Thumbs"
	content.add_child(thumbs)

	return section


func _find_set(set_id: int):
	for s in asset_sets:
		if s["id"] == set_id:
			return s
	return {}


func _on_set_png_pressed(set_id: int) -> void:
	if OS.has_feature("web"):
		_pick_file_web("image/png", true, set_id)
	else:
		_pick_file_desktop("*.png;PNG Images", func(path): _load_png_for_set(set_id, path))


func _on_set_json_pressed(set_id: int) -> void:
	if OS.has_feature("web"):
		_pick_file_web(".json", false, set_id)
	else:
		_pick_file_desktop("*.json;JSON Data", func(path): _load_json_for_set(set_id, path))


func _pick_file_desktop(filter: String, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([filter])
	dialog.file_selected.connect(func(path): callback.call(path); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))


func _pick_file_web(accept: String, is_png: bool, set_id: int) -> void:
	if not JavaScriptBridge:
		return
	var cb: Callable = _load_png_from_web.bind(set_id) if is_png else _load_json_from_web.bind(set_id)
	var js_cb = JavaScriptBridge.create_callback(cb)
	JavaScriptBridge.eval("""
	(function() {
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = '%s';
		input.style.display = 'none';
		document.body.appendChild(input);
		input.onchange = function(e) {
			var file = e.target.files[0];
			if (!file) { document.body.removeChild(input); return; }
			var reader = new FileReader();
			reader.onload = function(ev) { %s(ev.target.result); document.body.removeChild(input); };
			reader.readAs%s(file);
		};
		input.click();
	})();
	""" % [accept, js_cb, "ArrayBuffer" if is_png else "Text"])


func _load_png_for_set(set_id: int, path: String) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var image := Image.new()
	if image.load(path) == OK:
		s["sheet_texture"] = ImageTexture.create_from_image(image)
		s["png_path"] = path.get_file()
		_update_set_ui(set_id)
		_try_build_set(set_id)


func _load_json_for_set(set_id: int, path: String) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		_parse_json_for_set(set_id, file.get_as_text())
		s["json_path"] = path.get_file()
		file.close()
		_update_set_ui(set_id)
		_try_build_set(set_id)


func _load_png_from_web(set_id: int, args: Array) -> void:
	if args.size() == 0:
		return
	var byte_array: PackedByteArray
	if args[0] is PackedByteArray:
		byte_array = args[0]
	else:
		var raw = JavaScriptBridge.eval("""
			(function() {
				if (!window._hermes_png_buffer) return [];
				var b = window._hermes_png_buffer;
				var arr = [];
				for (var i = 0; i < b.byteLength; i++) arr.push(b[i]);
				return arr;
			})();
		""")
		if raw is Array:
			byte_array = PackedByteArray(raw)
	var image := Image.new()
	if image.load_png_from_buffer(byte_array) == OK:
		var s = _find_set(set_id)
		if not s.is_empty():
			s["sheet_texture"] = ImageTexture.create_from_image(image)
			s["png_path"] = "web_upload.png"
			_update_set_ui(set_id)
			_try_build_set(set_id)


func _load_json_from_web(set_id: int, args: Array) -> void:
	if args.size() > 0:
		_parse_json_for_set(set_id, str(args[0]))
		var s = _find_set(set_id)
		if not s.is_empty():
			s["json_path"] = "web_upload.json"
			_update_set_ui(set_id)
			_try_build_set(set_id)


func _parse_json_for_set(set_id: int, text: String) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return
	s["frames"] = []
	if parsed is Dictionary and parsed.has("frames"):
		for frame in parsed["frames"]:
			var f: Dictionary = frame.get("frame", {})
			s["frames"].append({
				"filename": frame.get("filename", ""),
				"x": int(f.get("x", 0)), "y": int(f.get("y", 0)),
				"w": int(f.get("w", 0)), "h": int(f.get("h", 0)),
			})
	elif parsed is Array:
		for item in parsed:
			s["frames"].append({
				"filename": item.get("name", item.get("filename", "")),
				"x": int(item.get("x", 0)), "y": int(item.get("y", 0)),
				"w": int(item.get("width", item.get("w", 0))),
				"h": int(item.get("height", item.get("h", 0))),
			})


func _try_build_set(set_id: int) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	if s["sheet_texture"] == null or s["frames"].size() == 0:
		return

	s["textures"] = []
	for frame in s["frames"]:
		var atlas := AtlasTexture.new()
		atlas.atlas = s["sheet_texture"]
		atlas.region = Rect2(frame["x"], frame["y"], frame["w"], frame["h"])
		s["textures"].append(atlas)

	# Populate thumbnails inside this set's section
	var section: VBoxContainer = s["section"]
	var content = section.get_node_or_null("Content")
	if content:
		var thumbs = content.get_node_or_null("Thumbs")
		if thumbs:
			for child in thumbs.get_children():
				child.queue_free()
			for i in range(s["textures"].size()):
				var thumb_panel := Panel.new()
				thumb_panel.custom_minimum_size = Vector2(50, 50)
				var tex_rect := TextureRect.new()
				tex_rect.texture = s["textures"][i]
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
				thumb_panel.add_child(tex_rect)

				# Wire hover preview + click-to-paint
				var local_idx := i
				var sid := set_id
				thumb_panel.gui_input.connect(_on_asset_gui_input.bind(sid, local_idx))
				thumb_panel.mouse_entered.connect(_on_thumb_hover.bind(s["textures"][local_idx]))
				thumb_panel.mouse_exited.connect(_hide_preview)

				thumbs.add_child(thumb_panel)


func _update_set_ui(set_id: int) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var section: VBoxContainer = s["section"]
	var content = section.get_node_or_null("Content")
	if not content:
		return
	var png_label: Label = content.find_child("PngLabel", true, false)
	var json_label: Label = content.find_child("JsonLabel", true, false)
	var png_trash: Button = content.find_child("PngTrash", true, false)
	var json_trash: Button = content.find_child("JsonTrash", true, false)

	if png_label:
		if s["png_path"] != "":
			png_label.text = s["png_path"]
			if png_trash:
				png_trash.visible = true
		else:
			png_label.text = "Load Sprite Sheet (.png)"
			if png_trash:
				png_trash.visible = false

	if json_label:
		if s["json_path"] != "":
			json_label.text = s["json_path"]
			if json_trash:
				json_trash.visible = true
		else:
			json_label.text = "Load JSON Data (.json)"
			if json_trash:
				json_trash.visible = false


func _on_set_remove_pressed(set_id: int) -> void:
	_pending_removal_id = set_id
	_confirm_dialog.popup_centered()


func _remove_asset_set(set_id: int) -> void:
	var idx := -1
	for i in range(asset_sets.size()):
		if asset_sets[i]["id"] == set_id:
			idx = i
			break
	if idx < 0:
		return
	var s = asset_sets[idx]

	# Remove placed sprites from this set
	var to_remove: Array = []
	for sprite in placed_sprites:
		if sprite.get_meta("set_id", -1) == set_id:
			to_remove.append(sprite)
	for sprite in to_remove:
		placed_sprites.erase(sprite)
		sprite.queue_free()

	if s["section"]:
		s["section"].queue_free()
	asset_sets.remove_at(idx)


# ════════════════════════════════════════════════════════════
# Phase 3: Click-To-Paint
# ════════════════════════════════════════════════════════════

func _on_thumb_hover(texture: Texture2D) -> void:
	_show_preview(texture)


func _on_asset_gui_input(event: InputEvent, set_id: int, local_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s = _find_set(set_id)
		if not s.is_empty() and local_idx < s["textures"].size():
			active_asset_index = local_idx
			active_asset_texture = s["textures"][local_idx]
			_highlight_selected_in_set(set_id, local_idx)


func _highlight_selected_in_set(active_set_id: int, active_local_idx: int) -> void:
	# Clear all highlights across all sets
	for s in asset_sets:
		if not s.has("section"):
			continue
		var section: VBoxContainer = s["section"]
		var content = section.get_node_or_null("Content")
		if not content:
			continue
		var thumbs = content.get_node_or_null("Thumbs")
		if not thumbs:
			continue
		for i in range(thumbs.get_child_count()):
			var panel = thumbs.get_child(i)
			if panel is Panel:
				panel.remove_theme_stylebox_override("panel")
				if s["id"] == active_set_id and i == active_local_idx:
					var sel := StyleBoxFlat.new()
					sel.bg_color = Color(0.2, 0.2, 0.25)
					sel.border_color = Color(0.6, 0.8, 1.0)
					sel.set_border_width_all(2)
					sel.set_content_margin_all(0)
					panel.add_theme_stylebox_override("panel", sel)


func _on_canvas_gui_input(event: InputEvent) -> void:
	if active_asset_index < 0 or active_asset_texture == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_asset_at_click(event.position)


func _place_asset_at_click(container_pos: Vector2) -> void:
	var vp_size := Vector2(sub_viewport.size)
	var container_size := Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return
	var vp_pos := container_pos * (vp_size / container_size)
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	var world_pos := (vp_pos - vp_size * 0.5) / cam.zoom + cam.position
	_place_asset(world_pos)


func _place_asset(world_pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = active_asset_texture
	sprite.position = world_pos
	sprite.z_index = int(world_pos.y) + 1000

	var set_id := -1
	for s in asset_sets:
		if active_asset_texture in s["textures"]:
			set_id = s["id"]
			break

	sprite.set_meta("set_id", set_id)
	sprite.set_meta("base_scale", Vector2(1.0, 1.0))

	asset_drop_zone.add_child(sprite)
	placed_sprites.append(sprite)


# ════════════════════════════════════════════════════════════
# Preview Popup
# ════════════════════════════════════════════════════════════

func _setup_preview() -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.visible = false
	_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.12, 0.15)
	sb.border_color = Color(0.45, 0.45, 0.55)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	_preview_panel.add_theme_stylebox_override("panel", sb)
	add_child(_preview_panel)
	_preview_tex = TextureRect.new()
	_preview_tex.custom_minimum_size = Vector2(180, 180)
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_panel.add_child(_preview_tex)


func _show_preview(texture: Texture2D) -> void:
	_preview_tex.texture = texture
	_preview_panel.visible = true
	var mp := get_global_mouse_position()
	var ps := Vector2(200, 200)
	var pos := mp + Vector2(16, 16)
	pos.x = minf(pos.x, size.x - ps.x)
	pos.y = minf(pos.y, size.y - ps.y)
	pos.x = maxf(pos.x, 0.0)
	pos.y = maxf(pos.y, 0.0)
	_preview_panel.position = pos


func _hide_preview() -> void:
	_preview_panel.visible = false


# ════════════════════════════════════════════════════════════
# Auto-load test assets
# ════════════════════════════════════════════════════════════

func _auto_load_test_assets() -> void:
	_on_add_assets_pressed()
	var set_id = asset_sets[0]["id"]

	var tex = load("res://assets/sprites/steam-interior-items3.png") as Texture2D
	if tex:
		asset_sets[0]["sheet_texture"] = tex
		asset_sets[0]["png_path"] = "steam-interior-items3.png"

	var file = FileAccess.open("res://assets/sprites/steam-interior-items3_tp-array.json", FileAccess.READ)
	if file:
		_parse_json_for_set(set_id, file.get_as_text())
		asset_sets[0]["json_path"] = "steam-interior-items3_tp-array.json"
		file.close()

	_update_set_ui(set_id)
	_try_build_set(set_id)
