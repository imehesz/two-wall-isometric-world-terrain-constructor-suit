extends Control

## Two-Wall Isometric Terrain Constructor
## Phase 1: UI Framework & Canvas Setup
## Phase 2: Multi-set file importer
## Phase 3: Per-set asset grid & click-to-paint
## Phase 4: Selection & Fine-Tune Inspector Engine

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
# Phase 4 references
@onready var toolbar: HBoxContainer = %Toolbar
@onready var insert_button: Button = %InsertButton
@onready var select_button: Button = %SelectButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var inspector_section: VBoxContainer = %ObjectInspectorSection
@onready var inspector_content: VBoxContainer = inspector_section.get_node("Content")

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
var selected_sprite: Sprite2D = null
var undo_stack: Array = []
var redo_stack: Array = []

# Selection indicators (created programmatically)
var _indicator_layer: CanvasLayer = null
var _sel_outline: Line2D = null
var _del_bg: Polygon2D = null
var _del_bar1: Line2D = null
var _del_bar2: Line2D = null
var _delete_dialog: ConfirmationDialog = null

# Inspector rows
var _inspector_rows: Dictionary = {}

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
	_setup_toolbar()
	_setup_selection_indicators()
	_setup_auto_repeat()
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
# Phase 4: Toolbar
# ════════════════════════════════════════════════════════════

func _setup_toolbar() -> void:
	insert_button.pressed.connect(_on_tool_changed.bind(ToolMode.INSERT))
	select_button.pressed.connect(_on_tool_changed.bind(ToolMode.SELECT))
	undo_button.pressed.connect(_undo)
	redo_button.pressed.connect(_redo)
	_update_toolbar_ui()
	_update_undo_redo_buttons()


func _on_tool_changed(tool: ToolMode) -> void:
	current_tool = tool
	_update_toolbar_ui()

	if tool == ToolMode.SELECT:
		# Dim asset thumbnails to indicate they can't be used for painting
		asset_sections_container.modulate = Color(0.5, 0.5, 0.5, 0.5)
	else:
		asset_sections_container.modulate = Color.WHITE
		_deselect_sprite()

	# Deselect active paint asset when switching to select
	if tool == ToolMode.SELECT:
		active_asset_index = -1
		active_asset_texture = null
		_clear_asset_highlights()


func _update_toolbar_ui() -> void:
	var active_sb := StyleBoxFlat.new()
	active_sb.bg_color = Color(0.3, 0.4, 0.6)
	active_sb.set_corner_radius_all(3)
	active_sb.set_content_margin_all(4)

	var inactive_sb := StyleBoxFlat.new()
	inactive_sb.bg_color = Color(0.15, 0.15, 0.18)
	inactive_sb.set_corner_radius_all(3)
	inactive_sb.set_content_margin_all(4)

	if current_tool == ToolMode.INSERT:
		insert_button.add_theme_stylebox_override("normal", active_sb)
		select_button.add_theme_stylebox_override("normal", inactive_sb)
	else:
		insert_button.add_theme_stylebox_override("normal", inactive_sb)
		select_button.add_theme_stylebox_override("normal", active_sb)


func _update_undo_redo_buttons() -> void:
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()


# ════════════════════════════════════════════════════════════
# Phase 4: Auto-Repeat (+/- hold)
# ════════════════════════════════════════════════════════════

var _repeat_timer: Timer
var _repeat_prop: String = ""
var _repeat_base_step: float = 0.0


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
			if selected_sprite == sprite:
				_deselect_sprite()
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
	_update_selection_dots()
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
			if selected_sprite == sprite:
				_deselect_sprite()
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
	_update_selection_dots()
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
	asset_drop_zone.add_child(sprite)
	placed_sprites.append(sprite)
	return sprite


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed:
				_redo()
			else:
				_undo()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()


# ════════════════════════════════════════════════════════════
# Phase 4: Selection
# ════════════════════════════════════════════════════════════

func _setup_selection_indicators() -> void:
	# CanvasLayer = separate render pass, always on top
	_indicator_layer = CanvasLayer.new()
	_indicator_layer.layer = 10
	sub_viewport.add_child(_indicator_layer)

	# Selection rectangle outline (Line2D)
	_sel_outline = Line2D.new()
	_sel_outline.width = 2.0
	_sel_outline.default_color = Color(0.4, 0.7, 1.0, 0.9)
	_sel_outline.visible = false
	_indicator_layer.add_child(_sel_outline)

	# Delete icon: dark bg square + two red diagonal lines
	_del_bg = Polygon2D.new()
	_del_bg.color = Color(0, 0, 0, 0.85)
	var hs := 9.0
	_del_bg.polygon = PackedVector2Array([
		Vector2(-hs, -hs), Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs)])
	_del_bg.visible = false
	_indicator_layer.add_child(_del_bg)
	_del_bar1 = Line2D.new()
	_del_bar1.width = 2.0
	_del_bar1.default_color = Color(1.0, 0.3, 0.3)
	_del_bar1.points = PackedVector2Array([Vector2(-4, -4), Vector2(4, 4)])
	_del_bar1.visible = false
	_indicator_layer.add_child(_del_bar1)
	_del_bar2 = Line2D.new()
	_del_bar2.width = 2.0
	_del_bar2.default_color = Color(1.0, 0.3, 0.3)
	_del_bar2.points = PackedVector2Array([Vector2(4, -4), Vector2(-4, 4)])
	_del_bar2.visible = false
	_indicator_layer.add_child(_del_bar2)

	# Delete confirmation dialog
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.dialog_text = "Delete this asset from the canvas?"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)


func _select_sprite(sprite: Sprite2D) -> void:
	selected_sprite = sprite
	_update_selection_dots()
	_update_inspector()


func _deselect_sprite() -> void:
	selected_sprite = null
	_sel_outline.visible = false
	_del_bg.visible = false
	_del_bar1.visible = false
	_del_bar2.visible = false
	inspector_content.visible = false
	var btn = inspector_section.get_node_or_null("HeaderButton")
	if btn:
		btn.text = "▶ Object Inspector"


func _update_selection_dots() -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		_deselect_sprite()
		return

	var sprite = selected_sprite
	var tex = sprite.texture
	if tex == null:
		return

	var tex_size = tex.get_size() * sprite.scale
	var half = tex_size * 0.5
	var pos = sprite.position

	# Convert world corners → viewport screen positions (CanvasLayer is screen-space)
	var tl = pos + Vector2(-half.x, -half.y)
	var tr = pos + Vector2(half.x, -half.y)
	var br = pos + Vector2(half.x, half.y)
	var bl = pos + Vector2(-half.x, half.y)

	_sel_outline.points = PackedVector2Array([
		_world_to_vp(tl), _world_to_vp(tr),
		_world_to_vp(br), _world_to_vp(bl), _world_to_vp(tl)])
	_sel_outline.visible = true

	var del_vp = _world_to_vp(tr + Vector2(4, -4))
	_del_bg.position = del_vp
	_del_bg.visible = true
	_del_bar1.position = del_vp
	_del_bar1.visible = true
	_del_bar2.position = del_vp
	_del_bar2.visible = true


func _delete_selected_sprite() -> void:
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return
	var sprite = selected_sprite
	var action = {
		"type": "delete",
		"sprite": sprite,
		"sprite_data": _get_sprite_data(sprite),
	}
	_push_undo(action)
	placed_sprites.erase(sprite)
	sprite.queue_free()
	_deselect_sprite()


func _is_near_trash(world_pos: Vector2) -> bool:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return false
	if _del_bg == null or not _del_bg.visible:
		return false
	var click_vp = _world_to_vp(world_pos)
	return click_vp.distance_to(_del_bg.position) < 14.0


func _world_to_vp(world_pos: Vector2) -> Vector2:
	var cam = sub_viewport.get_node("Camera2D") as Camera2D
	var vp_size = Vector2(sub_viewport.size)
	return (world_pos - cam.position) * cam.zoom + vp_size * 0.5


func _hit_test(world_pos: Vector2) -> Sprite2D:
	# Check in reverse order — top-most (highest z_index) first
	for i in range(placed_sprites.size() - 1, -1, -1):
		var sprite = placed_sprites[i]
		var tex = sprite.texture
		if tex == null:
			continue
		var tex_size = tex.get_size() * sprite.scale
		var rect = Rect2(sprite.position - tex_size * 0.5, tex_size)
		if rect.has_point(world_pos):
			return sprite
	return null


# ════════════════════════════════════════════════════════════
# Phase 4: Inspector
# ════════════════════════════════════════════════════════════

func _update_inspector() -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return

	# Clear existing rows
	for child in inspector_content.get_children():
		child.queue_free()
	_inspector_rows.clear()

	# Show inspector
	inspector_content.visible = true
	var btn = inspector_section.get_node_or_null("HeaderButton")
	if btn:
		btn.text = "▼ Object Inspector"

	# Asset label
	var name_label := Label.new()
	name_label.text = "Asset: " + str(selected_sprite.get_meta("set_id", "?"))
	name_label.clip_text = true
	inspector_content.add_child(name_label)

	var sep := HSeparator.new()
	inspector_content.add_child(sep)

	# Property rows
	_add_inspector_row("move_x", "Move X", MOVE_STEP)
	_add_inspector_row("move_y", "Move Y", MOVE_STEP)
	_add_inspector_row("depth", "Depth Z", DEPTH_STEP)
	_add_inspector_row("scale", "Scale", SCALE_STEP)
	_add_inspector_row("rotate", "Rotation", ROTATE_STEP)

	# Flip H
	var flip_row := HBoxContainer.new()
	var flip_label := Label.new()
	flip_label.text = "Flip H"
	flip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_row.add_child(flip_label)
	var flip_val := Label.new()
	flip_val.custom_minimum_size = Vector2(50, 0)
	flip_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip_val.text = "OFF" if not selected_sprite.flip_h else "ON"
	flip_row.add_child(flip_val)
	var flip_btn := Button.new()
	flip_btn.text = "Flip"
	flip_btn.custom_minimum_size = Vector2(52, 0)
	flip_btn.pressed.connect(_on_flip_pressed)
	flip_row.add_child(flip_btn)
	inspector_content.add_child(flip_row)
	_inspector_rows["flip"] = {"value_label": flip_val}

	_refresh_inspector_values()


func _add_inspector_row(prop_name: String, label_text: String, step: float) -> void:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(28, 0)
	minus_btn.button_down.connect(_on_repeat_start.bind(prop_name, -step))
	minus_btn.button_up.connect(_on_repeat_stop)
	row.add_child(minus_btn)

	var value_label := Label.new()
	value_label.text = "0.0"
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 0)
	plus_btn.button_down.connect(_on_repeat_start.bind(prop_name, step))
	plus_btn.button_up.connect(_on_repeat_stop)
	row.add_child(plus_btn)

	inspector_content.add_child(row)
	_inspector_rows[prop_name] = {
		"label": label, "value_label": value_label,
		"minus": minus_btn, "plus": plus_btn
	}


func _on_inspector_minus(prop_name: String, base_step: float) -> void:
	var multiplier = _get_modifier_multiplier()
	_apply_transform(prop_name, -base_step * multiplier)


func _on_inspector_plus(prop_name: String, base_step: float) -> void:
	var multiplier = _get_modifier_multiplier()
	_apply_transform(prop_name, base_step * multiplier)


func _get_modifier_multiplier() -> float:
	if Input.is_key_pressed(KEY_SHIFT):
		return 10.0
	elif Input.is_key_pressed(KEY_ALT):
		return 0.1
	return 1.0


func _apply_transform(prop_name: String, delta: float) -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return

	var sprite = selected_sprite
	var action := {"type": "", "sprite": sprite}

	match prop_name:
		"move_x":
			var old_pos = sprite.position
			var new_pos = old_pos + Vector2(delta, 0)
			var old_z = sprite.z_index
			var new_z = int(new_pos.y) + 1000
			action["type"] = "move"
			action["old_pos"] = old_pos
			action["new_pos"] = new_pos
			action["old_z_index"] = old_z
			action["new_z_index"] = new_z
			sprite.position = new_pos
			sprite.z_index = new_z
		"move_y":
			var old_pos = sprite.position
			var new_pos = old_pos + Vector2(0, delta)
			action["type"] = "move"
			action["old_pos"] = old_pos
			action["new_pos"] = new_pos
			action["old_z_index"] = sprite.z_index
			action["new_z_index"] = sprite.z_index
			sprite.position = new_pos
		"depth":
			var old_z = sprite.z_index
			var new_z = old_z + int(delta)
			action["type"] = "move"
			action["old_pos"] = sprite.position
			action["new_pos"] = sprite.position
			action["old_z_index"] = old_z
			action["new_z_index"] = new_z
			sprite.z_index = new_z
		"scale":
			var old_scale = sprite.scale
			var new_scale = old_scale + Vector2(delta, delta)
			new_scale = Vector2(maxf(new_scale.x, 0.1), maxf(new_scale.y, 0.1))
			action["type"] = "scale"
			action["old_scale"] = old_scale
			action["new_scale"] = new_scale
			sprite.scale = new_scale
		"rotate":
			var old_rot = sprite.rotation_degrees
			var new_rot = old_rot + delta
			action["type"] = "rotate"
			action["old_rotation"] = old_rot
			action["new_rotation"] = new_rot
			sprite.rotation_degrees = new_rot

	_push_undo(action)
	_update_selection_dots()
	_refresh_inspector_values()


func _on_flip_pressed() -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return
	var sprite = selected_sprite
	var action = {
		"type": "flip",
		"sprite": sprite,
		"old_flip": sprite.flip_h,
		"new_flip": !sprite.flip_h,
	}
	_push_undo(action)
	sprite.flip_h = !sprite.flip_h
	_refresh_inspector_values()


func _refresh_inspector_values() -> void:
	if selected_sprite == null or not is_instance_valid(selected_sprite):
		return
	var sprite = selected_sprite

	if _inspector_rows.has("move_x"):
		_inspector_rows["move_x"]["value_label"].text = "%.1f" % sprite.position.x
	if _inspector_rows.has("move_y"):
		_inspector_rows["move_y"]["value_label"].text = "%.1f" % sprite.position.y
	if _inspector_rows.has("depth"):
		_inspector_rows["depth"]["value_label"].text = "%d" % sprite.z_index
	if _inspector_rows.has("scale"):
		_inspector_rows["scale"]["value_label"].text = "%.2f" % sprite.scale.x
	if _inspector_rows.has("rotate"):
		_inspector_rows["rotate"]["value_label"].text = "%.1f°" % sprite.rotation_degrees
	if _inspector_rows.has("flip"):
		_inspector_rows["flip"]["value_label"].text = "ON" if sprite.flip_h else "OFF"


# ════════════════════════════════════════════════════════════
# Collapsible Sections
# ════════════════════════════════════════════════════════════

func _setup_collapsibles() -> void:
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

	# Populate thumbnails
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
# Phase 3: Click-To-Paint & Selection
# ════════════════════════════════════════════════════════════

func _on_thumb_hover(texture: Texture2D) -> void:
	_show_preview(texture)


func _on_asset_gui_input(event: InputEvent, set_id: int, local_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Switch to INSERT mode when clicking a thumbnail
		if current_tool != ToolMode.INSERT:
			_on_tool_changed(ToolMode.INSERT)
		var s = _find_set(set_id)
		if not s.is_empty() and local_idx < s["textures"].size():
			active_asset_index = local_idx
			active_asset_texture = s["textures"][local_idx]
			_highlight_selected_in_set(set_id, local_idx)


func _highlight_selected_in_set(active_set_id: int, active_local_idx: int) -> void:
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


func _clear_asset_highlights() -> void:
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


func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_tool == ToolMode.INSERT:
			# Insert mode — place asset
			if active_asset_index >= 0 and active_asset_texture != null:
				_place_asset_at_click(event.position)
		elif current_tool == ToolMode.SELECT:
			# Select mode — check trash first, then hit test
			var world_pos = _container_to_world(event.position)
			if _is_near_trash(world_pos):
				_delete_selected_sprite()
			else:
				var hit = _hit_test(world_pos)
				if hit:
					_select_sprite(hit)
				else:
					_deselect_sprite()


func _container_to_world(container_pos: Vector2) -> Vector2:
	var vp_size := Vector2(sub_viewport.size)
	var container_size := Vector2(sub_viewport_container.size)
	if container_size.x == 0 or container_size.y == 0:
		return Vector2.ZERO
	var vp_pos := container_pos * (vp_size / container_size)
	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	return (vp_pos - vp_size * 0.5) / cam.zoom + cam.position


func _place_asset_at_click(container_pos: Vector2) -> void:
	var world_pos = _container_to_world(container_pos)
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

	# Undo
	var action = {
		"type": "place",
		"sprite": sprite,
		"sprite_data": _get_sprite_data(sprite),
	}
	_push_undo(action)


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
