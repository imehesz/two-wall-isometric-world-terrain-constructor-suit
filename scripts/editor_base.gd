extends Control
## Two-Wall Isometric Terrain Constructor — Base Class
## State, constants, camera, room, undo/redo, zoom/pan, settings persistence.

# ── References ───────────────────────────────────────────────
@onready var sub_viewport: SubViewport = %SubViewport
@onready var sub_viewport_container: SubViewportContainer = %SubViewportContainer
@onready var canvas_panel: MarginContainer = %CanvasPanel
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
# Phase 4 references
@onready var insert_button: Button = %InsertButton
@onready var select_button: Button = %SelectButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var inspector_section: VBoxContainer = %ObjectInspectorSection
@onready var inspector_content: VBoxContainer = inspector_section.get_node("Content")
# Phase 7 references
@onready var save_button: Button = %SaveButton
@onready var download_backup_button: Button = %DownloadBackupButton
@onready var import_backup_button: Button = %ImportBackupButton
# Phase 9 references
@onready var grid_button: Button = %GridButton
@onready var help_button: Button = %HelpButton

# ── Constants ────────────────────────────────────────────────
const ISO_WIDTH := 600.0
const ISO_HEIGHT := 300.0
const WALL_HEIGHT := 200.0
const COLOR_BG := Color(0.12, 0.11, 0.14)
const COLOR_ROOM := Color(0.55, 0.65, 0.85)
const MAX_UNDO := 20

# Transform increments (base values)
const MOVE_STEP := 1.0
const DEPTH_STEP := 100.0
const SCALE_STEP := 0.1
const ROTATE_STEP := 5.0
const ZOOM_STEP := 0.15
const ZOOM_MIN := 0.1
const ZOOM_MAX := 5.0
const SETTINGS_KEY := "twiwcs_settings"

# ── Enums ────────────────────────────────────────────────────
enum ToolMode { INSERT, SELECT }

# ── State ────────────────────────────────────────────────────
var active_asset_index: int = -1
var active_asset_texture: AtlasTexture = null
var placed_sprites: Array = []
var _next_set_id: int = 0
var asset_sets: Array = []
var _set_count: int = 0

# Phase 4 state
var current_tool: ToolMode = ToolMode.INSERT
var _selected_sprites: Array = []
var undo_stack: Array = []
var redo_stack: Array = []

# Selection indicators (per-sprite, managed via pool)
var _indicator_layer: CanvasLayer = null
var _sprite_indicators: Dictionary = {}  # sprite → {outline, del_bg, del_bar1, del_bar2}
var _indicator_pool: Array = []  # recycled indicator sets
var _delete_dialog: ConfirmationDialog = null
var _pending_delete_sprite: Sprite2D = null

# Inspector rows
var _inspector_rows: Dictionary = {}

# ── Preview ──────────────────────────────────────────────────
var _preview_panel: PanelContainer
var _preview_tex: TextureRect

# ── Confirm dialog ───────────────────────────────────────────
var _confirm_dialog: ConfirmationDialog
var _pending_removal_id: int = -1

# Phase 5: Pan state
var _is_panning: bool = false

# Phase 7: Save/Load
var _js_db_ready: bool = false
var _has_saved_project: bool = false
var _save_confirm_dialog: ConfirmationDialog
var _load_confirm_dialog: ConfirmationDialog
var _status_label: Label = null

# Auto-repeat state
var _repeat_timer: Timer
var _repeat_prop: String = ""
var _repeat_base_step: float = 0.0


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
# Phase 4: Auto-Repeat (+/- hold)
# ════════════════════════════════════════════════════════════

func _setup_auto_repeat() -> void:
	_repeat_timer = Timer.new()
	_repeat_timer.wait_time = 0.15
	_repeat_timer.one_shot = false
	_repeat_timer.timeout.connect(_on_repeat_timeout)
	add_child(_repeat_timer)


func _on_repeat_start(prop_name: String, base_step: float) -> void:
	_repeat_prop = prop_name
	_repeat_base_step = base_step
	# Apply one immediate step
	var multiplier = _get_modifier_multiplier()
	_apply_transform(prop_name, base_step * multiplier)
	_repeat_timer.start()


func _on_repeat_stop() -> void:
	_repeat_timer.stop()


func _on_repeat_timeout() -> void:
	var multiplier = _get_modifier_multiplier()
	_apply_transform(_repeat_prop, _repeat_base_step * multiplier)


# ════════════════════════════════════════════════════════════
# Phase 4: Undo / Redo
# ════════════════════════════════════════════════════════════

func _push_undo(action: Dictionary) -> void:
	undo_stack.append(action)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_undo_redo_buttons()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var action = undo_stack.pop_back()
	_reverse_action(action)
	redo_stack.append(action)
	_update_undo_redo_buttons()


func _redo() -> void:
	if redo_stack.is_empty():
		return
	var action = redo_stack.pop_back()
	_replay_action(action)
	undo_stack.append(action)
	_update_undo_redo_buttons()


func _reverse_action(action: Dictionary) -> void:
	match action["type"]:
		"place":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				placed_sprites.erase(sprite)
				sprite.queue_free()
			if sprite in _selected_sprites:
				_selected_sprites.erase(sprite)
				_free_sprite_indicators(sprite)
		"delete":
			var sprite_data = action["sprite_data"]
			_restore_sprite(sprite_data)
		"move":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.position = action["old_pos"]
				sprite.z_index = action["old_z_index"]
		"scale":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.scale = action["old_scale"]
		"rotate":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.rotation_degrees = action["old_rotation"]
		"flip":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.flip_h = action["old_flip"]
	_refresh_all_indicators()
	_refresh_inspector_values()


func _replay_action(action: Dictionary) -> void:
	match action["type"]:
		"place":
			_restore_sprite(action["sprite_data"])
		"delete":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				placed_sprites.erase(sprite)
				sprite.queue_free()
			if sprite in _selected_sprites:
				_selected_sprites.erase(sprite)
				_free_sprite_indicators(sprite)
		"move":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.position = action["new_pos"]
				sprite.z_index = action["new_z_index"]
		"scale":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.scale = action["new_scale"]
		"rotate":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.rotation_degrees = action["new_rotation"]
		"flip":
			var sprite = action["sprite"]
			if is_instance_valid(sprite):
				sprite.flip_h = action["new_flip"]
	_refresh_all_indicators()
	_refresh_inspector_values()


func _get_sprite_data(sprite: Sprite2D) -> Dictionary:
	return {
		"texture": sprite.texture,
		"position": sprite.position,
		"scale": sprite.scale,
		"rotation": sprite.rotation_degrees,
		"flip_h": sprite.flip_h,
		"z_index": sprite.z_index,
		"set_id": sprite.get_meta("set_id", -1),
		"locked": sprite.get_meta("locked", false),
	}


func _restore_sprite(data: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = data["texture"]
	sprite.position = data["position"]
	sprite.scale = data["scale"]
	sprite.rotation_degrees = data["rotation"]
	sprite.flip_h = data["flip_h"]
	sprite.z_index = data["z_index"]
	sprite.set_meta("set_id", data["set_id"])
	sprite.set_meta("base_scale", Vector2(1.0, 1.0))
	sprite.set_meta("locked", data.get("locked", false))
	asset_drop_zone.add_child(sprite)
	placed_sprites.append(sprite)
	return sprite


# ════════════════════════════════════════════════════════════
# Phase 4: Modifier Multiplier
# ════════════════════════════════════════════════════════════

func _get_modifier_multiplier() -> float:
	if Input.is_key_pressed(KEY_SHIFT):
		return 10.0
	elif Input.is_key_pressed(KEY_ALT):
		return 0.1
	return 1.0


# ════════════════════════════════════════════════════════════
# Phase 5: Canvas Zoom & Pan
# ════════════════════════════════════════════════════════════

func _apply_zoom(delta: float, container_pos: Vector2) -> void:
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	var vp_size = Vector2(sub_viewport.size)
	var container_size = Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return
	# World position under cursor before zoom
	var vp_pos = container_pos * (vp_size / container_size)
	var world_before = (vp_pos - vp_size * 0.5) / cam.zoom + cam.position
	# Apply new zoom
	var old_zoom = cam.zoom.x
	var new_zoom = clampf(old_zoom + delta, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(new_zoom, new_zoom)
	# Adjust camera so same world point stays under cursor
	var world_after = (vp_pos - vp_size * 0.5) / cam.zoom + cam.position
	cam.position += world_before - world_after


func _do_pan(relative: Vector2) -> void:
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	var vp_size = Vector2(sub_viewport.size)
	var container_size = Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return
	var scale_factor = vp_size / container_size
	cam.position -= (relative * scale_factor) / cam.zoom


# ════════════════════════════════════════════════════════════
# Phase 5: Settings Persistence (localStorage)
# ════════════════════════════════════════════════════════════

func _save_settings(_color: Color = Color()) -> void:
	if not JavaScriptBridge:
		return
	var s = {
		"bg": [canvas_bg_color.color.r, canvas_bg_color.color.g, canvas_bg_color.color.b],
		"room": [room_color_picker.color.r, room_color_picker.color.g, room_color_picker.color.b],
	}
	var j = JSON.stringify(s)
	JavaScriptBridge.eval("localStorage.setItem('%s','%s')" % [SETTINGS_KEY, j])


func _load_settings() -> void:
	if not JavaScriptBridge:
		return
	var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % SETTINGS_KEY)
	if raw == null:
		return
	var p = JSON.parse_string(str(raw))
	if p == null:
		return
	if p.has("bg"):
		var a = p["bg"]
		var c = Color(a[0], a[1], a[2])
		canvas_bg_color.color = c
		_apply_bg_color(c)
	if p.has("room"):
		var a = p["room"]
		var c = Color(a[0], a[1], a[2])
		room_color_picker.color = c
		_apply_room_color(c)


func _container_to_world(container_pos: Vector2) -> Vector2:
	var vp_size := Vector2(sub_viewport.size)
	var container_size := Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return Vector2.ZERO
	var vp_pos := container_pos * (vp_size / container_size)
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	return (vp_pos - vp_size * 0.5) / cam.zoom + cam.position


func _world_to_vp(world_pos: Vector2) -> Vector2:
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	var vp_size = Vector2(sub_viewport.size)
	return (world_pos - cam.position) * cam.zoom + vp_size * 0.5


# ════════════════════════════════════════════════════════════
# Virtual stubs — override in child class
# ════════════════════════════════════════════════════════════

## Called by _push_undo / _undo / _redo to refresh toolbar button states.
func _update_undo_redo_buttons() -> void:
	pass


## Called by undo/redo to clean up selection indicators for a sprite.
func _free_sprite_indicators(_sprite: Sprite2D) -> void:
	pass


## Called by undo/redo to refresh all selection indicator visuals.
func _refresh_all_indicators() -> void:
	pass


## Called by undo/redo to update inspector row values.
func _refresh_inspector_values() -> void:
	pass


## Called by auto-repeat timer to apply a transform delta to selected sprites.
func _apply_transform(_prop_name: String, _delta: float) -> void:
	pass
