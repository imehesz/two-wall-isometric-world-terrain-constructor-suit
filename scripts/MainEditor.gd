extends Control

## Two-Wall Isometric Terrain Constructor
## Phase 1: UI Framework & Canvas Setup
## Phase 2: HTML5 File I/O Importer
## Phase 3: Asset Library Grid & Click-To-Paint Placement

# ── Phase 1 References ──────────────────────────────────────
@onready var sub_viewport: SubViewport = %SubViewport
@onready var sub_viewport_container: SubViewportContainer = %SubViewportContainer
@onready var canvas_panel: PanelContainer = %CanvasPanel
@onready var canvas_bg_color: ColorPickerButton = %CanvasBgColorPicker
@onready var room_color_picker: ColorPickerButton = %RoomColorPicker
@onready var floor_poly: Polygon2D = %FloorPolygon
@onready var wall_back_poly: Polygon2D = %WallBackPolygon
@onready var wall_left_poly: Polygon2D = %WallLeftPolygon
@onready var room_outline: Line2D = %RoomOutline
@onready var asset_drop_zone: Node2D = %AssetDropZone

# ── Phase 2/3 References ────────────────────────────────────
@onready var import_png_button: Button = %ImportPngButton
@onready var import_json_button: Button = %ImportJsonButton
@onready var import_status: Label = %ImportStatus
@onready var asset_grid: VBoxContainer = %AssetGrid

# ── Constants ────────────────────────────────────────────────
const ISO_WIDTH := 600.0
const ISO_HEIGHT := 300.0
const WALL_HEIGHT := 200.0
const COLOR_BG := Color(0.12, 0.11, 0.14)
const COLOR_ROOM := Color(0.55, 0.65, 0.85)

# ── Import State ─────────────────────────────────────────────
var sheet_texture: Texture2D = null
var frames: Array = []           # [{filename, x, y, w, h}, ...]
var asset_textures: Array = []   # [AtlasTexture, ...]
var active_asset_index: int = -1 # -1 = nothing selected (not painting)
var placed_sprites: Array = []   # All Sprite2D nodes on canvas


func _ready() -> void:
	# Phase 1 setup
	sub_viewport.transparent_bg = true
	_apply_bg_color(COLOR_BG)
	_apply_room_color(COLOR_ROOM)
	_draw_room()
	call_deferred("_fit_camera")

	canvas_bg_color.color_changed.connect(_apply_bg_color)
	room_color_picker.color_changed.connect(_apply_room_color)

	# Phase 2: Import buttons
	import_png_button.pressed.connect(_on_import_png_pressed)
	import_json_button.pressed.connect(_on_import_json_pressed)

	# Phase 3: Canvas click-to-paint + hover preview
	_setup_preview()
	sub_viewport_container.gui_input.connect(_on_canvas_gui_input)

	# Auto-load test assets so you don't have to click every time
	call_deferred("_auto_load_test_assets")


func _auto_load_test_assets() -> void:
	var tex = load("res://assets/sprites/steam-interior-items3.png") as Texture2D
	if tex:
		sheet_texture = tex
	var file = FileAccess.open("res://assets/sprites/steam-interior-items3_tp-array.json", FileAccess.READ)
	if file:
		_parse_json_text(file.get_as_text())
		file.close()


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
# Phase 2: File I/O Importer
# ════════════════════════════════════════════════════════════

func _on_import_png_pressed() -> void:
	if OS.has_feature("web"):
		_pick_file_web("image/png", true)
	else:
		_pick_file_desktop("*.png;PNG Images", _on_png_selected)


func _on_import_json_pressed() -> void:
	if OS.has_feature("web"):
		_pick_file_web(".json", false)
	else:
		_pick_file_desktop("*.json;JSON Data", _on_json_selected)


func _pick_file_desktop(filter: String, callback: Callable) -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([filter])
	dialog.file_selected.connect(func(path): callback.call(path); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))


func _pick_file_web(accept: String, is_png: bool) -> void:
	if not JavaScriptBridge:
		import_status.text = "File dialogs not available in this build"
		return
	var cb = JavaScriptBridge.create_callback(_on_web_png_data if is_png else _on_web_json_data)
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
			reader.onload = function(ev) {
				%s(ev.target.result);
				document.body.removeChild(input);
			};
			reader.readAs%s(file);
		};
		input.click();
	})();
	""" % [accept, cb, "ArrayBuffer" if is_png else "Text"])


func _on_png_selected(path: String) -> void:
	var image := Image.new()
	var err := image.load(path)
	if err == OK:
		sheet_texture = ImageTexture.create_from_image(image)
		_update_status()
		_try_build_atlases()
	else:
		import_status.text = "Failed to load image"


func _on_json_selected(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		import_status.text = "Failed to open JSON"
		return
	_parse_json_text(file.get_as_text())
	file.close()


func _on_web_png_data(args: Array) -> void:
	if args.size() == 0:
		return
	# args[0] is a JS ArrayBuffer — convert to PackedByteArray
	var buffer = args[0]
	var byte_array: PackedByteArray
	if buffer is PackedByteArray:
		byte_array = buffer
	else:
		# Fallback: try reading from JS
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

	var image = Image.new()
	var err = image.load_png_from_buffer(byte_array)
	if err == OK:
		sheet_texture = ImageTexture.create_from_image(image)
		_update_status()
		_try_build_atlases()
	else:
		import_status.text = "Failed to decode PNG"


func _on_web_json_data(args: Array) -> void:
	if args.size() > 0:
		_parse_json_text(str(args[0]))


func _parse_json_text(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if parsed == null:
		import_status.text = "Invalid JSON"
		return

	# Support both TexturePacker Array format and flat format
	if parsed is Dictionary and parsed.has("frames"):
		# TexturePacker JSON Array format
		frames.clear()
		for frame in parsed["frames"]:
			var f: Dictionary = frame.get("frame", {})
			frames.append({
				"filename": frame.get("filename", ""),
				"x": int(f.get("x", 0)),
				"y": int(f.get("y", 0)),
				"w": int(f.get("w", 0)),
				"h": int(f.get("h", 0)),
			})
	elif parsed is Array:
		# Flat format (like steampunk-test: [{name, x, y, width, height}])
		frames.clear()
		for item in parsed:
			frames.append({
				"filename": item.get("name", item.get("filename", "")),
				"x": int(item.get("x", 0)),
				"y": int(item.get("y", 0)),
				"w": int(item.get("width", item.get("w", 0))),
				"h": int(item.get("height", item.get("h", 0))),
			})
	else:
		import_status.text = "Unrecognised JSON format"
		return

	_update_status()
	_try_build_atlases()


func _try_build_atlases() -> void:
	if sheet_texture == null or frames.size() == 0:
		return
	_build_atlases()


func _build_atlases() -> void:
	asset_textures.clear()
	for frame in frames:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet_texture
		atlas.region = Rect2(frame["x"], frame["y"], frame["w"], frame["h"])
		asset_textures.append(atlas)
	_populate_asset_grid()
	_update_status()


func _update_status() -> void:
	var parts: PackedStringArray = []
	parts.append("Sheet: %s" % ("loaded" if sheet_texture else "—"))
	parts.append("JSON: %s" % ("%d frames" % frames.size() if frames.size() > 0 else "—"))
	if active_asset_index >= 0 and active_asset_index < frames.size():
		parts.append("Active: %s" % frames[active_asset_index]["filename"])
	import_status.text = " | ".join(parts)


# ════════════════════════════════════════════════════════════
# Phase 3: Asset Library & Click-To-Paint
# ════════════════════════════════════════════════════════════

var _preview_panel: PanelContainer
var _preview_tex: TextureRect


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


func _populate_asset_grid() -> void:
	for child in asset_grid.get_children():
		child.queue_free()

	# Calculate how many 50px+4px-gap items fit across the panel
	var item_w := 54.0  # 50px + 4px gap
	var grid_w := asset_grid.size.x if asset_grid.size.x > 0 else 350.0
	var columns := maxi(int(grid_w / item_w), 1)
	var row: HBoxContainer = null

	for i in range(asset_textures.size()):
		if i % columns == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			asset_grid.add_child(row)

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(50, 50)

		var tex_rect := TextureRect.new()
		tex_rect.texture = asset_textures[i]
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(tex_rect)

		panel.gui_input.connect(_on_asset_gui_input.bind(i))
		panel.mouse_entered.connect(_on_grid_hover.bind(i))
		panel.mouse_exited.connect(_hide_preview)
		row.add_child(panel)

	_update_grid_highlights()


func _on_grid_hover(index: int) -> void:
	if index >= 0 and index < asset_textures.size():
		_show_preview(asset_textures[index])


func _on_asset_selected(index: int) -> void:
	if active_asset_index == index:
		active_asset_index = -1  # Toggle off
	else:
		active_asset_index = index
	_update_grid_highlights()
	_update_status()


func _update_grid_highlights() -> void:
	var idx := 0
	for row in asset_grid.get_children():
		if row is HBoxContainer:
			for panel in row.get_children():
				if panel is Panel:
					panel.modulate = Color(1.3, 1.3, 1.6) if idx == active_asset_index else Color.WHITE
					idx += 1


func _on_asset_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_asset_selected(index)


func _on_canvas_gui_input(event: InputEvent) -> void:
	if active_asset_index < 0:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_asset_at_click(event.position)


func _place_asset_at_click(container_pos: Vector2) -> void:
	var vp_size := Vector2(sub_viewport.size)
	var container_size := Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return

	# Container coords → SubViewport coords (stretch = true, 1:1 after scale)
	var vp_pos := container_pos * (vp_size / container_size)

	# SubViewport coords → World coords (account for Camera2D)
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	var world_pos := (vp_pos - vp_size * 0.5) / cam.zoom + cam.position

	_place_asset(world_pos)


func _place_asset(world_pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = asset_textures[active_asset_index]
	sprite.position = world_pos
	sprite.z_index = int(world_pos.y) + 1000  # Offset so sprites always render above room (z=0)

	# Metadata for Phase 6 export
	sprite.set_meta("asset_id", frames[active_asset_index]["filename"])
	sprite.set_meta("asset_index", active_asset_index)
	sprite.set_meta("base_scale", Vector2(1.0, 1.0))

	asset_drop_zone.add_child(sprite)
	placed_sprites.append(sprite)
