extends "res://scripts/editor_base.gd"
## Two-Wall Isometric Terrain Constructor — Main Editor
## UI setup, tools, selection, indicators, inspector, assets, save/load.


# ════════════════════════════════════════════════════════════
# Initialization
# ════════════════════════════════════════════════════════════

func _ready() -> void:
	_apply_bg_color(COLOR_BG)
	_apply_room_color(COLOR_ROOM)
	_draw_room()
	call_deferred("_fit_camera")
	canvas_bg_color.color_changed.connect(_apply_bg_color)
	canvas_bg_color.color_changed.connect(_save_settings)
	room_color_picker.color_changed.connect(_apply_room_color)
	room_color_picker.color_changed.connect(_save_settings)

	_setup_preview()
	_setup_confirm_dialog()
	_setup_collapsibles()
	_setup_toolbar()
	_setup_selection_indicators()
	_setup_auto_repeat()
	add_assets_button.pressed.connect(_on_add_assets_pressed)
	sub_viewport_container.gui_input.connect(_on_canvas_gui_input)

	call_deferred("_auto_load_test_assets")
	call_deferred("_load_settings")
	call_deferred("_init_db")

	# Phase 6/7: Wire buttons
	export_json_button.pressed.connect(_export_json)
	save_button.pressed.connect(_on_save_pressed)
	download_backup_button.pressed.connect(_export_twiwcs)
	import_backup_button.pressed.connect(_import_twiwcs)

	_setup_save_load_dialogs()

	# Version label (bottom-right)
	var dt = Time.get_datetime_dict_from_system()
	var datetime_str = "%04d%02d%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
	var version_label := Label.new()
	version_label.text = "v.0.1." + datetime_str
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.offset_left = -200
	version_label.offset_top = -30
	version_label.offset_right = -8
	version_label.offset_bottom = -8
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	add_child(version_label)


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


func _unhandled_input(event: InputEvent) -> void:
	# Phase 5: Stop panning if mouse released outside canvas
	if _is_panning and event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_is_panning = false
			return
	# Phase 5: Pan motion outside canvas
	if _is_panning and event is InputEventMouseMotion:
		_do_pan(event.relative)
		return
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed:
				_redo()
			else:
				_undo()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_I:
			_on_tool_changed(ToolMode.INSERT)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_J:
			_on_tool_changed(ToolMode.SELECT)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()


# ════════════════════════════════════════════════════════════
# Phase 4: Selection (multi-select)
# ════════════════════════════════════════════════════════════

func _setup_selection_indicators() -> void:
	_indicator_layer = CanvasLayer.new()
	_indicator_layer.layer = 10
	sub_viewport.add_child(_indicator_layer)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.dialog_text = "Delete this asset from the canvas?"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)


func _create_indicator_set() -> Dictionary:
	var hs := 9.0
	var outline := Line2D.new()
	outline.width = 2.0
	outline.default_color = Color(0.4, 0.7, 1.0, 0.9)
	outline.visible = false
	_indicator_layer.add_child(outline)

	var del_bg := Polygon2D.new()
	del_bg.color = Color(0, 0, 0, 0.85)
	del_bg.polygon = PackedVector2Array([
		Vector2(-hs, -hs), Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs)])
	del_bg.visible = false
	_indicator_layer.add_child(del_bg)

	var del_bar1 := Line2D.new()
	del_bar1.width = 2.0
	del_bar1.default_color = Color(1.0, 0.3, 0.3)
	del_bar1.points = PackedVector2Array([Vector2(-4, -4), Vector2(4, 4)])
	del_bar1.visible = false
	_indicator_layer.add_child(del_bar1)

	var del_bar2 := Line2D.new()
	del_bar2.width = 2.0
	del_bar2.default_color = Color(1.0, 0.3, 0.3)
	del_bar2.points = PackedVector2Array([Vector2(4, -4), Vector2(-4, 4)])
	del_bar2.visible = false
	_indicator_layer.add_child(del_bar2)

	# Lock background
	var lock_bg := Polygon2D.new()
	lock_bg.color = Color(0, 0, 0, 0.85)
	lock_bg.polygon = PackedVector2Array([
		Vector2(-hs, -hs), Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs)])
	lock_bg.visible = false
	_indicator_layer.add_child(lock_bg)

	# Lock shackle (inverted U shape)
	var lock_shackle := Line2D.new()
	lock_shackle.width = 2.0
	lock_shackle.default_color = Color(0.5, 0.5, 0.5)
	lock_shackle.points = PackedVector2Array([
		Vector2(-3, 0), Vector2(-3, -4), Vector2(3, -4), Vector2(3, 0)])
	lock_shackle.visible = false
	_indicator_layer.add_child(lock_shackle)

	# Lock body (rectangle)
	var lock_body := Polygon2D.new()
	lock_body.color = Color(0.5, 0.5, 0.5)
	lock_body.polygon = PackedVector2Array([
		Vector2(-4, 0), Vector2(4, 0), Vector2(4, 5), Vector2(-4, 5)])
	lock_body.visible = false
	_indicator_layer.add_child(lock_body)

	return {"outline": outline, "del_bg": del_bg, "del_bar1": del_bar1, "del_bar2": del_bar2,
		"lock_bg": lock_bg, "lock_shackle": lock_shackle, "lock_body": lock_body}


func _get_or_create_indicators(sprite: Sprite2D) -> Dictionary:
	if _sprite_indicators.has(sprite):
		return _sprite_indicators[sprite]
	var inds: Dictionary
	if _indicator_pool.size() > 0:
		inds = _indicator_pool.pop_back()
	else:
		inds = _create_indicator_set()
	_sprite_indicators[sprite] = inds
	return inds


func _hide_indicators(sprite: Sprite2D) -> void:
	if not _sprite_indicators.has(sprite):
		return
	var inds = _sprite_indicators[sprite]
	inds["outline"].visible = false
	inds["del_bg"].visible = false
	inds["del_bar1"].visible = false
	inds["del_bar2"].visible = false
	inds["lock_bg"].visible = false
	inds["lock_shackle"].visible = false
	inds["lock_body"].visible = false
	_indicator_pool.append(inds)
	_sprite_indicators.erase(sprite)


func _select_sprite(sprite: Sprite2D, additive: bool = false) -> void:
	if additive:
		if sprite in _selected_sprites:
			_selected_sprites.erase(sprite)
		else:
			_selected_sprites.append(sprite)
	else:
		_selected_sprites.clear()
		_selected_sprites.append(sprite)
	_refresh_all_indicators()
	_update_inspector()


func _deselect_sprite() -> void:
	_selected_sprites.clear()
	_free_all_indicators()
	inspector_content.visible = false
	var btn = inspector_section.get_node_or_null("HeaderButton")
	if btn:
		btn.text = "▶ Object Inspector"


func _last_selected() -> Sprite2D:
	if _selected_sprites.is_empty():
		return null
	var sprite = _selected_sprites.back()
	if is_instance_valid(sprite):
		return sprite
	return null


func _free_all_indicators() -> void:
	for sprite in _sprite_indicators.keys():
		var inds = _sprite_indicators[sprite]
		inds["outline"].visible = false
		inds["del_bg"].visible = false
		inds["del_bar1"].visible = false
		inds["del_bar2"].visible = false
		inds["lock_bg"].visible = false
		inds["lock_shackle"].visible = false
		inds["lock_body"].visible = false
		_indicator_pool.append(inds)
	_sprite_indicators.clear()


func _refresh_all_indicators() -> void:
	# Hide indicators for deselected sprites
	var to_hide: Array = []
	for sprite in _sprite_indicators.keys():
		if sprite not in _selected_sprites:
			to_hide.append(sprite)
	for sprite in to_hide:
		_hide_indicators(sprite)
	# Show indicators for selected sprites
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		_update_sprite_indicator(sprite)


func _update_sprite_indicator(sprite: Sprite2D) -> void:
	var inds = _get_or_create_indicators(sprite)
	var tex = sprite.texture
	if tex == null:
		return
	var tex_size = tex.get_size() * sprite.scale
	var half = tex_size * 0.5
	var pos = sprite.position
	var tl = pos + Vector2(-half.x, -half.y)
	var tr = pos + Vector2(half.x, -half.y)
	var br = pos + Vector2(half.x, half.y)
	var bl = pos + Vector2(-half.x, half.y)

	# Update outline (5 points for closed rect) — must convert to viewport coords for CanvasLayer
	inds["outline"].points = PackedVector2Array([
		_world_to_vp(tl), _world_to_vp(tr), _world_to_vp(br),
		_world_to_vp(bl), _world_to_vp(tl)])
	inds["outline"].visible = true

	# Update delete icon position
	var del_vp = _world_to_vp(tr + Vector2(4, -4))
	inds["del_bg"].position = del_vp
	inds["del_bar1"].position = del_vp
	inds["del_bar2"].position = del_vp
	inds["del_bg"].visible = true
	inds["del_bar1"].visible = true
	inds["del_bar2"].visible = true

	# Update lock icon position (16px below delete icon)
	var lock_vp = _world_to_vp(tr + Vector2(4, 16))
	inds["lock_bg"].position = lock_vp
	inds["lock_shackle"].position = lock_vp
	inds["lock_body"].position = lock_vp
	inds["lock_bg"].visible = true
	inds["lock_shackle"].visible = true
	inds["lock_body"].visible = true

	# Lock color by state
	var locked = sprite.get_meta("locked", false)
	var lock_color = Color(1.0, 0.85, 0.2) if locked else Color(0.5, 0.5, 0.5)
	inds["lock_shackle"].default_color = lock_color
	inds["lock_body"].color = lock_color


func _free_sprite_indicators(sprite: Sprite2D) -> void:
	if not _sprite_indicators.has(sprite):
		return
	var inds = _sprite_indicators[sprite]
	inds["outline"].visible = false
	inds["del_bg"].visible = false
	inds["del_bar1"].visible = false
	inds["del_bar2"].visible = false
	inds["lock_bg"].visible = false
	inds["lock_shackle"].visible = false
	inds["lock_body"].visible = false
	_indicator_pool.append(inds)
	_sprite_indicators.erase(sprite)


func _hit_test(world_pos: Vector2) -> Sprite2D:
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


func _find_trash_at_world(world_pos: Vector2) -> Sprite2D:
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		var inds = _sprite_indicators.get(sprite, {})
		if inds.is_empty():
			continue
		var click_vp = _world_to_vp(world_pos)
		if click_vp.distance_to(inds["del_bg"].position) < 14.0:
			return sprite
	return null


func _find_lock_at_world(world_pos: Vector2) -> Sprite2D:
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		var inds = _sprite_indicators.get(sprite, {})
		if inds.is_empty():
			continue
		var click_vp = _world_to_vp(world_pos)
		if click_vp.distance_to(inds["lock_bg"].position) < 14.0:
			return sprite
	return null


func _toggle_lock_for_sprite(sprite: Sprite2D) -> void:
	var locked = sprite.get_meta("locked", false)
	sprite.set_meta("locked", not locked)
	_refresh_all_indicators()


func _delete_sprite(sprite: Sprite2D) -> void:
	_pending_delete_sprite = sprite
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_sprite == null or not is_instance_valid(_pending_delete_sprite):
		return
	var sprite = _pending_delete_sprite
	var action = {
		"type": "delete",
		"sprite": sprite,
		"sprite_data": _get_sprite_data(sprite),
	}
	_push_undo(action)
	_selected_sprites.erase(sprite)
	_free_sprite_indicators(sprite)
	placed_sprites.erase(sprite)
	sprite.queue_free()
	_pending_delete_sprite = null
	_refresh_all_indicators()
	_update_inspector()


# ════════════════════════════════════════════════════════════
# Phase 4: Inspector
# ════════════════════════════════════════════════════════════

func _update_inspector() -> void:
	var sprite = _last_selected()
	if sprite == null:
		inspector_content.visible = false
		var btn = inspector_section.get_node_or_null("HeaderButton")
		if btn:
			btn.text = "\u25b6 Object Inspector"
		return
	inspector_content.visible = true
	var hdr_btn = inspector_section.get_node_or_null("HeaderButton")
	if hdr_btn:
		hdr_btn.text = "\u25bc Object Inspector"
	# Clear existing rows
	for child in inspector_content.get_children():
		child.queue_free()
	_inspector_rows.clear()
	# Add rows
	_add_inspector_row("move_x", "Move X", MOVE_STEP)
	_add_inspector_row("move_y", "Move Y", MOVE_STEP)
	_add_inspector_row("depth", "Depth Z", DEPTH_STEP)
	_add_inspector_row("scale", "Scale", SCALE_STEP)
	_add_inspector_row("rotate", "Rotation", ROTATE_STEP)
	# Flip toggle
	var flip_row := HBoxContainer.new()
	var flip_label := Label.new()
	flip_label.text = "Flip H"
	flip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_row.add_child(flip_label)
	var flip_val := Label.new()
	flip_val.custom_minimum_size = Vector2(50, 0)
	flip_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip_val.text = "ON" if sprite.flip_h else "OFF"
	flip_row.add_child(flip_val)
	var flip_btn := Button.new()
	flip_btn.text = "Flip"
	flip_btn.custom_minimum_size = Vector2(52, 0)
	flip_btn.pressed.connect(_on_flip_pressed)
	flip_row.add_child(flip_btn)
	inspector_content.add_child(flip_row)
	_inspector_rows["flip"] = {"value_label": flip_val, "button": flip_btn}
	# Lock toggle
	var lock_row := HBoxContainer.new()
	var lock_label := Label.new()
	lock_label.text = "Lock"
	lock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock_row.add_child(lock_label)
	var lock_val := Label.new()
	lock_val.custom_minimum_size = Vector2(50, 0)
	lock_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_val.text = "ON" if sprite.get_meta("locked", false) else "OFF"
	lock_row.add_child(lock_val)
	var lock_btn := Button.new()
	lock_btn.text = "Lock"
	lock_btn.custom_minimum_size = Vector2(52, 0)
	lock_btn.pressed.connect(_on_lock_pressed)
	lock_row.add_child(lock_btn)
	inspector_content.add_child(lock_row)
	_inspector_rows["lock"] = {"value_label": lock_val, "button": lock_btn}
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


func _apply_transform(prop_name: String, delta: float) -> void:
	if _selected_sprites.is_empty():
		return
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		if sprite.get_meta("locked", false):
			continue
		var action := {"type": "", "sprite": sprite}
		match prop_name:
			"move_x":
				var old_pos = sprite.position
				var new_pos = old_pos + Vector2(delta, 0)
				action["type"] = "move"
				action["old_pos"] = old_pos
				action["new_pos"] = new_pos
				action["old_z_index"] = sprite.z_index
				action["new_z_index"] = sprite.z_index
				sprite.position = new_pos
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
	_refresh_all_indicators()
	_refresh_inspector_values()


func _on_flip_pressed() -> void:
	if _selected_sprites.is_empty():
		return
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		if sprite.get_meta("locked", false):
			continue
		var action = {
			"type": "flip",
			"sprite": sprite,
			"old_flip": sprite.flip_h,
			"new_flip": !sprite.flip_h,
		}
		_push_undo(action)
		sprite.flip_h = !sprite.flip_h
	_refresh_inspector_values()


func _on_lock_pressed() -> void:
	for sprite in _selected_sprites:
		if not is_instance_valid(sprite):
			continue
		var locked = sprite.get_meta("locked", false)
		sprite.set_meta("locked", not locked)
	_refresh_inspector_values()
	_refresh_all_indicators()


func _refresh_inspector_values() -> void:
	var sprite = _last_selected()
	if sprite == null:
		return
	if _inspector_rows.has("move_x"):
		_inspector_rows["move_x"]["value_label"].text = "%.1f" % sprite.position.x
	if _inspector_rows.has("move_y"):
		_inspector_rows["move_y"]["value_label"].text = "%.1f" % sprite.position.y
	if _inspector_rows.has("depth"):
		_inspector_rows["depth"]["value_label"].text = "%d" % sprite.z_index
	if _inspector_rows.has("scale"):
		_inspector_rows["scale"]["value_label"].text = "%.2f" % sprite.scale.x
	if _inspector_rows.has("rotate"):
		_inspector_rows["rotate"]["value_label"].text = "%.1f\u00b0" % sprite.rotation_degrees
	if _inspector_rows.has("flip"):
		_inspector_rows["flip"]["value_label"].text = "ON" if sprite.flip_h else "OFF"
	if _inspector_rows.has("lock"):
		_inspector_rows["lock"]["value_label"].text = "ON" if sprite.get_meta("locked", false) else "OFF"
		_inspector_rows["lock"]["button"].text = "Unlock" if sprite.get_meta("locked", false) else "Lock"


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
		var title := btn.text.replace("\u25bc ", "").replace("\u25b6 ", "")
		btn.pressed.connect(_toggle_section.bind(btn, content, title))


func _toggle_section(btn: Button, content: Control, title: String) -> void:
	content.visible = !content.visible
	btn.text = ("\u25bc " if content.visible else "\u25b6 ") + title


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
		"sheet_png_bytes": PackedByteArray(),
		"json_text": "",
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


## BUG FIX 1: Replaced broken JavaScriptBridge.create_callback approach
## with a polling model — JS stores result in window._twiwcs_file_data,
## a Timer polls from GDScript until the data arrives.
func _pick_file_web(accept: String, is_png: bool, set_id: int) -> void:
	if not JavaScriptBridge:
		return
	JavaScriptBridge.eval("window._twiwcs_file_data = null")
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
				if (%s) {
					var bytes = new Uint8Array(ev.target.result);
					var binary = '';
					for (var i = 0; i < bytes.byteLength; i++) {
						binary += String.fromCharCode(bytes[i]);
					}
					window._twiwcs_file_data = {type: 'png', data: window.btoa(binary)};
				} else {
					window._twiwcs_file_data = {type: 'json', data: ev.target.result};
				}
				document.body.removeChild(input);
			};
			reader.readAs%s(file);
		};
		input.click();
	})();
	""" % [accept, "true" if is_png else "false", "ArrayBuffer" if is_png else "Text"])
	var poll_timer = Timer.new()
	poll_timer.wait_time = 0.1
	poll_timer.one_shot = false
	add_child(poll_timer)
	poll_timer.timeout.connect(_poll_web_file_data.bind(set_id, poll_timer))
	poll_timer.start()


func _poll_web_file_data(set_id: int, timer: Timer) -> void:
	if not JavaScriptBridge:
		timer.stop()
		timer.queue_free()
		return
	var raw = JavaScriptBridge.eval("JSON.stringify(window._twiwcs_file_data)")
	if raw == null or raw == "null":
		return
	timer.stop()
	timer.queue_free()
	JavaScriptBridge.eval("window._twiwcs_file_data = null")
	var data = JSON.parse_string(str(raw))
	if data == null:
		return
	var file_type = data.get("type", "")
	var file_data = data.get("data", "")
	if file_type == "png" and file_data != "":
		_process_web_png(set_id, file_data)
	elif file_type == "json" and file_data != "":
		_process_web_json(set_id, file_data)


func _process_web_png(set_id: int, b64: String) -> void:
	var byte_array = Marshalls.base64_to_raw(b64)
	if byte_array.size() == 0:
		return
	var image := Image.new()
	if image.load_png_from_buffer(byte_array) == OK:
		var s = _find_set(set_id)
		if not s.is_empty():
			s["sheet_texture"] = ImageTexture.create_from_image(image)
			s["sheet_png_bytes"] = byte_array
			s["png_path"] = "web_upload.png"
			_update_set_ui(set_id)
			_try_build_set(set_id)


func _process_web_json(set_id: int, text: String) -> void:
	_parse_json_for_set(set_id, text)
	var s = _find_set(set_id)
	if not s.is_empty():
		s["json_text"] = text
		s["json_path"] = "web_upload.json"
		_update_set_ui(set_id)
		_try_build_set(set_id)


func _load_png_for_set(set_id: int, path: String) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var image := Image.new()
	if image.load(path) == OK:
		s["sheet_texture"] = ImageTexture.create_from_image(image)
		s["sheet_png_bytes"] = image.save_png_to_buffer()
		s["png_path"] = path.get_file()
		_update_set_ui(set_id)
		_try_build_set(set_id)


func _load_json_for_set(set_id: int, path: String) -> void:
	var s = _find_set(set_id)
	if s.is_empty():
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var text = file.get_as_text()
		_parse_json_for_set(set_id, text)
		s["json_text"] = text
		s["json_path"] = path.get_file()
		file.close()
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
		_selected_sprites.erase(sprite)
		_free_sprite_indicators(sprite)
		placed_sprites.erase(sprite)
		sprite.queue_free()

	if _selected_sprites.is_empty():
		_deselect_sprite()

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
	# ── Phase 5: Zoom (mouse wheel) ──
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(ZOOM_STEP, event.position)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(-ZOOM_STEP, event.position)
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_is_panning = true
			return
	# ── Phase 5: Stop panning on release ──
	if event is InputEventMouseButton and not event.pressed:
		if _is_panning and (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT):
			_is_panning = false
			return
	# ── Phase 5: Pan (mouse motion while panning) ──
	if event is InputEventMouseMotion and _is_panning:
		_do_pan(event.relative)
		return
	# ── Left click: insert or select ──
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_tool == ToolMode.INSERT:
			if active_asset_index >= 0 and active_asset_texture != null:
				_place_asset_at_click(event.position)
		elif current_tool == ToolMode.SELECT:
			var world_pos = _container_to_world(event.position)
			var trash_sprite = _find_trash_at_world(world_pos)
			if trash_sprite:
				_delete_sprite(trash_sprite)
			else:
				var lock_sprite = _find_lock_at_world(world_pos)
				if lock_sprite:
					_toggle_lock_for_sprite(lock_sprite)
				else:
					var hit = _hit_test(world_pos)
					var additive = Input.is_key_pressed(KEY_SHIFT)
					if hit:
						_select_sprite(hit, additive)
					else:
						_deselect_sprite()


# ════════════════════════════════════════════════════════════
# Phase 5: Place Asset
# ════════════════════════════════════════════════════════════

func _place_asset_at_click(container_pos: Vector2) -> void:
	var world_pos = _container_to_world(container_pos)
	_place_asset(world_pos)


func _place_asset(world_pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = active_asset_texture
	sprite.position = world_pos
	sprite.z_index = int(world_pos.y) + 1000

	var set_id := -1
	var asset_id := ""
	var frame_idx := -1
	for s in asset_sets:
		if active_asset_texture in s["textures"]:
			set_id = s["id"]
			frame_idx = s["textures"].find(active_asset_texture)
			if frame_idx >= 0 and frame_idx < s["frames"].size():
				asset_id = s["frames"][frame_idx]["filename"]
			break

	sprite.set_meta("set_id", set_id)
	sprite.set_meta("asset_id", asset_id)
	sprite.set_meta("frame_index", frame_idx)
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

## BUG FIX 2: Use load() + get_image() instead of Image.new().load()
## which fails on HTML5 exports.
func _auto_load_test_assets() -> void:
	_on_add_assets_pressed()
	var set_id = asset_sets[0]["id"]

	var tex = load("res://assets/sprites/steam-interior-items3.png") as Texture2D
	if tex:
		var image = tex.get_image()
		asset_sets[0]["sheet_texture"] = ImageTexture.create_from_image(image)
		asset_sets[0]["sheet_png_bytes"] = image.save_png_to_buffer()
		asset_sets[0]["png_path"] = "steam-interior-items3.png"

	var file = FileAccess.open("res://assets/sprites/steam-interior-items3_tp-array.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		_parse_json_for_set(set_id, text)
		asset_sets[0]["json_text"] = text
		asset_sets[0]["json_path"] = "steam-interior-items3_tp-array.json"
		file.close()

	_update_set_ui(set_id)
	_try_build_set(set_id)


# ════════════════════════════════════════════════════════════
# Phase 6: JSON Layout Export
# ════════════════════════════════════════════════════════════

func _serialize_layout() -> String:
	var objects := []
	for sprite in placed_sprites:
		if not is_instance_valid(sprite):
			continue
		var pos = sprite.position
		var sc = sprite.scale
		objects.append({
			"asset_id": sprite.get_meta("asset_id", ""),
			"set_id": sprite.get_meta("set_id", -1),
			"position": {"x": pos.x, "y": pos.y},
			"scale": {"x": sc.x, "y": sc.y},
			"rotation": sprite.rotation_degrees,
			"flip_h": sprite.flip_h,
			"z_index": sprite.z_index,
			"locked": sprite.get_meta("locked", false),
		})
	return JSON.stringify({"layout_version": "1.0", "objects": objects})


func _export_json() -> void:
	var json_str = _serialize_layout()
	if OS.has_feature("web"):
		if JavaScriptBridge:
			JavaScriptBridge.eval("""(function() {
				var s = %s;
				var blob = new Blob([s], {type: 'application/json'});
				var url = URL.createObjectURL(blob);
				var a = document.createElement('a');
				a.href = url;
				a.download = 'map_layout.json';
				document.body.appendChild(a);
				a.click();
				document.body.removeChild(a);
				URL.revokeObjectURL(url);
			})();""" % json_str)
	else:
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.json;JSON Data"])
		dialog.file_selected.connect(func(path): _write_json_file(path, json_str); dialog.queue_free())
		dialog.canceled.connect(func(): dialog.queue_free())
		add_child(dialog)
		dialog.popup_centered(Vector2i(800, 600))


func _write_json_file(path: String, json_str: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()


# ════════════════════════════════════════════════════════════
# Phase 7: IndexedDB Persistence
# ════════════════════════════════════════════════════════════

func _init_db() -> void:
	print("[TWIWCS] _init_db() called — JavaScriptBridge=", JavaScriptBridge)
	if not JavaScriptBridge:
		push_warning("[TWIWCS] _init_db: JavaScriptBridge is null — not running in HTML5?")
		return
	# Embedded JS — FileAccess can't read res://scripts/*.js from the PCK in HTML5 exports,
	# so the DB code lives inline here instead.
	JavaScriptBridge.eval(_TWIWCS_DB_JS)
	print("[TWIWCS] _init_db: eval(db_js) done")
	JavaScriptBridge.eval("window._twiwcs_db_init_result = null; window.TWIWCS_DB.init(function(d) { window._twiwcs_db_init_result = d; })")
	print("[TWIWCS] _init_db: eval(init) done — starting poll")
	_poll_db_result("_twiwcs_db_init_result", _on_db_init_complete)


const _TWIWCS_DB_JS := """
window.TWIWCS_DB = (function () {
	"use strict";
	const DB_NAME = "twiwcs_projects";
	const DB_VERSION = 1;
	const PROJECT_KEY = "current";
	let _db = null;
	function _ok(cb, data) { if (cb) cb(JSON.stringify(data)); }
	function _err(cb, msg) { if (cb) cb(JSON.stringify({ success: false, error: String(msg) })); }
	function init(callback) {
		if (_db) { _ok(callback, { success: true }); return; }
		var req = indexedDB.open(DB_NAME, DB_VERSION);
		req.onupgradeneeded = function (e) {
			var db = e.target.result;
			if (!db.objectStoreNames.contains("projects")) {
				db.createObjectStore("projects", { keyPath: "name" });
			}
			if (!db.objectStoreNames.contains("assets")) {
				var store = db.createObjectStore("assets", { keyPath: "key" });
				store.createIndex("project_name", "project_name", { unique: false });
			}
		};
		req.onsuccess = function (e) { _db = e.target.result; _ok(callback, { success: true }); };
		req.onerror = function (e) { _err(callback, e.target.error ? e.target.error.message : "open failed"); };
	}
	function hasSavedProject(callback) {
		if (!_db) { _err(callback, "DB not initialized"); return; }
		var tx = _db.transaction("projects", "readonly");
		var req = tx.objectStore("projects").get(PROJECT_KEY);
		req.onsuccess = function (e) { _ok(callback, { success: true, exists: !!e.target.result }); };
		req.onerror = function (e) { _err(callback, e.target.error ? e.target.error.message : "check failed"); };
	}
	function saveProject(layoutJson, assetsJson, callback) {
		if (!_db) { _err(callback, "DB not initialized"); return; }
		var tx = _db.transaction(["projects", "assets"], "readwrite");
		var projStore = tx.objectStore("projects");
		var assetStore = tx.objectStore("assets");
		projStore.put({ name: PROJECT_KEY, layout_json: layoutJson });
		var idx = assetStore.index("project_name");
		var range = IDBKeyRange.only(PROJECT_KEY);
		var oldKeys = [];
		var cursorReq = idx.openCursor(range);
		cursorReq.onsuccess = function (e) {
			var cursor = e.target.result;
			if (cursor) { oldKeys.push(cursor.primaryKey); cursor["continue"](); }
			else {
				for (var i = 0; i < oldKeys.length; i++) { assetStore["delete"](oldKeys[i]); }
				var assets = JSON.parse(assetsJson);
				for (var j = 0; j < assets.length; j++) {
					assetStore.put({
						key: PROJECT_KEY + "::" + assets[j].filename,
						project_name: PROJECT_KEY,
						filename: assets[j].filename,
						png_base64: assets[j].png_base64,
						json_metadata: assets[j].json_metadata,
						json_path: assets[j].json_path || "",
						set_id: assets[j].set_id
					});
				}
			}
		};
		tx.oncomplete = function () { _ok(callback, { success: true }); };
		tx.onerror = function (e) { _err(callback, e.target.error ? e.target.error.message : "save failed"); };
	}
	function loadProject(callback) {
		if (!_db) { _err(callback, "DB not initialized"); return; }
		var tx = _db.transaction(["projects", "assets"], "readonly");
		var projReq = tx.objectStore("projects").get(PROJECT_KEY);
		projReq.onsuccess = function (e) {
			var project = e.target.result;
			if (!project) { _err(callback, "No saved project"); return; }
			var assetStore = tx.objectStore("assets");
			var idx = assetStore.index("project_name");
			var allReq = idx.getAll(IDBKeyRange.only(PROJECT_KEY));
			allReq.onsuccess = function (e2) {
				var rawAssets = e2.target.result || [];
				var assets = [];
				for (var i = 0; i < rawAssets.length; i++) {
					assets.push({ filename: rawAssets[i].filename, png_base64: rawAssets[i].png_base64, json_metadata: rawAssets[i].json_metadata, json_path: rawAssets[i].json_path || "", set_id: rawAssets[i].set_id });
				}
				_ok(callback, { success: true, layout_json: project.layout_json, assets_json: JSON.stringify(assets) });
			};
			allReq.onerror = function (e2) { _err(callback, e2.target.error ? e2.target.error.message : "assets fetch failed"); };
		};
		projReq.onerror = function (e) { _err(callback, e.target.error ? e.target.error.message : "project fetch failed"); };
	}
	function exportTwiwcs(projectName, dataJson) {
		var blob = new Blob([dataJson], { type: "application/json" });
		var url = URL.createObjectURL(blob);
		var a = document.createElement("a");
		a.href = url; a.download = (projectName || "project") + ".twiwcs";
		document.body.appendChild(a); a.click(); document.body.removeChild(a);
		URL.revokeObjectURL(url);
	}
	function importTwiwcs(callback) {
		var input = document.createElement("input");
		input.type = "file"; input.accept = ".twiwcs"; input.style.display = "none";
		document.body.appendChild(input);
		input.onchange = function (e) {
			var file = e.target.files[0];
			if (!file) { document.body.removeChild(input); _err(callback, "No file selected"); return; }
			var reader = new FileReader();
			reader.onload = function (ev) { document.body.removeChild(input); if (callback) callback(ev.target.result); };
			reader.onerror = function () { document.body.removeChild(input); _err(callback, "Read failed"); };
			reader.readAsText(file);
		};
		input.click();
	}
	return { init: init, hasSavedProject: hasSavedProject, saveProject: saveProject, loadProject: loadProject, exportTwiwcs: exportTwiwcs, importTwiwcs: importTwiwcs };
})();
"""


func _on_db_init_complete(json_str: String) -> void:
	print("[TWIWCS] _on_db_init_complete: ", json_str)
	var result = JSON.parse_string(json_str)
	if result and result.get("success", false):
		_js_db_ready = true
		print("[TWIWCS] DB init SUCCESS — checking for saved project")
		_check_for_saved_project()
	else:
		push_warning("[TWIWCS] DB init FAILED: ", result.get("error", "unknown") if result else "null result")


func _check_for_saved_project() -> void:
	JavaScriptBridge.eval("window._twiwcs_check_result = null; window.TWIWCS_DB.hasSavedProject(function(d) { window._twiwcs_check_result = d; })")
	_poll_db_result("_twiwcs_check_result", _on_check_complete)


func _on_check_complete(json_str: String) -> void:
	var result = JSON.parse_string(json_str)
	if result and result.get("success", false) and result.get("exists", false):
		_has_saved_project = true
		_load_confirm_dialog.popup_centered()
	else:
		_has_saved_project = false



func _poll_db_result(var_name: String, callback: Callable, interval: float = 0.1) -> void:
	print("[TWIWCS] _poll_db_result: starting poll for '", var_name, "' every ", interval, "s")
	var timer = Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	var tick_count := 0
	timer.timeout.connect(func():
		tick_count += 1
		if tick_count == 10:
			print("[TWIWCS] poll '", var_name, "': still waiting after 1s...")
		elif tick_count == 50:
			print("[TWIWCS] poll '", var_name, "': still waiting after 5s — something may be wrong")
		_poll_db_tick(var_name, callback, timer)
	)
	add_child(timer)
	timer.start()


func _poll_db_tick(var_name: String, callback: Callable, timer: Timer) -> void:
	var raw = JavaScriptBridge.eval("window['%s']" % var_name)
	if raw == null or raw == "null" or raw == "":
		return
	print("[TWIWCS] _poll_db_tick('", var_name, "'): got result → ", str(raw).substr(0, 200))
	timer.stop()
	timer.queue_free()
	JavaScriptBridge.eval("window['%s'] = null" % var_name)
	callback.call(str(raw))


func _serialize_asset_sets_for_save() -> String:
	var sets_data := []
	for s in asset_sets:
		var png_b64 = Marshalls.raw_to_base64(s["sheet_png_bytes"]) if s["sheet_png_bytes"].size() > 0 else ""
		sets_data.append({
			"set_id": s["id"],
			"filename": s["png_path"],
			"json_path": s.get("json_path", ""),
			"png_base64": png_b64,
			"json_metadata": s["json_text"],
		})
	return JSON.stringify(sets_data)


func _setup_save_load_dialogs() -> void:
	# Save overwrite confirmation
	_save_confirm_dialog = ConfirmationDialog.new()
	_save_confirm_dialog.dialog_text = "A project is already saved. Overwrite it?"
	_save_confirm_dialog.get_ok_button().text = "Overwrite"
	_save_confirm_dialog.get_cancel_button().text = "Cancel"
	_save_confirm_dialog.confirmed.connect(_save_project)
	add_child(_save_confirm_dialog)
	# Load prompt on startup
	_load_confirm_dialog = ConfirmationDialog.new()
	_load_confirm_dialog.dialog_text = "A saved project was found. Load it?"
	_load_confirm_dialog.get_ok_button().text = "Load"
	_load_confirm_dialog.get_cancel_button().text = "New Project"
	_load_confirm_dialog.confirmed.connect(_load_project)
	add_child(_load_confirm_dialog)


func _on_save_pressed() -> void:
	print("[TWIWCS] Save button pressed — _js_db_ready=", _js_db_ready, " _has_saved_project=", _has_saved_project)
	if not _js_db_ready:
		_show_status("Save failed: DB not initialized (run as HTML5 export)")
		return
	if _has_saved_project:
		_save_confirm_dialog.popup_centered()
	else:
		_save_project()


func _save_project() -> void:
	print("[TWIWCS] _save_project called — _js_db_ready=", _js_db_ready)
	if not _js_db_ready:
		_show_status("Save failed: DB not ready")
		return
	var layout_json = _serialize_layout()
	var assets_json = _serialize_asset_sets_for_save()
	print("[TWIWCS] layout_json length=", layout_json.length(), " assets_json length=", assets_json.length())
	if OS.has_feature("web") and JavaScriptBridge:
		# Push layout (small) and assets (large, chunked) into a single
		# JS array, then hand everything to saveProject in ONE eval.
		JavaScriptBridge.eval("window._twiwcs_savelayout = %s" % layout_json)
		JavaScriptBridge.eval("window._twiwcs_savechunks = []")
		var chunk_size = 500000
		var pos := 0
		while pos < assets_json.length():
			var end := mini(pos + chunk_size, assets_json.length())
			var chunk := assets_json.substr(pos, end - pos)
			JavaScriptBridge.eval("window._twiwcs_savechunks.push(%s)" % JSON.stringify(chunk))
			pos = end
		# Assemble + save in one shot: join chunks → parse → call saveProject
		# This keeps the heavy work entirely in JS, minimal eval() calls into wasm.
		print("[TWIWCS] calling saveProject in one shot...")
		JavaScriptBridge.eval("""(function() {
			var assetsStr = window._twiwcs_savechunks.join('');
			window._twiwcs_savechunks = null;
			window._twiwcs_save_result = null;
			window.TWIWCS_DB.saveProject(
				JSON.stringify(window._twiwcs_savelayout),
				assetsStr,
				function(d) { window._twiwcs_save_result = d; });
		})()""")
		print("[TWIWCS] saveProject eval done — starting poll")
		_poll_db_result("_twiwcs_save_result", _on_db_save_complete)
	else:
		_show_status("Save only works in HTML5 export")


func _on_db_save_complete(json_str: String) -> void:
	var result = JSON.parse_string(json_str)
	if result and result.get("success", false):
		_has_saved_project = true
		print("[TWIWCS] Project saved")
		_show_status("✅ Project saved")
	else:
		push_warning("[TWIWCS] Save failed: ", result.get("error", "unknown"))
		_show_status("❌ Save failed: " + str(result.get("error", "unknown")))


func _show_status(msg: String, duration: float = 4.0) -> void:
	print("[TWIWCS] ", msg)
	if _status_label == null:
		_status_label = Label.new()
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_status_label.add_theme_font_size_override("font_size", 14)
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		# Dark semi-transparent background
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.11, 0.14, 0.92)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(12)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.5, 0.7, 0.4)
		_status_label.add_theme_stylebox_override("normal", sb)
		# Position at bottom-center of canvas area
		_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_status_label.offset_left = -200
		_status_label.offset_right = 200
		_status_label.offset_top = -50
		_status_label.offset_bottom = -14
		_status_label.z_index = 100
		add_child(_status_label)
	_status_label.text = msg
	_status_label.visible = true
	# Auto-hide after duration
	if _status_label.has_meta("_hide_timer"):
		_status_label.get_meta("_hide_timer").queue_free()
	var timer := Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): _status_label.visible = false; timer.queue_free())
	_status_label.set_meta("_hide_timer", timer)
	add_child(timer)
	timer.start()




func _load_project() -> void:
	if not _js_db_ready:
		return
	JavaScriptBridge.eval("window._twiwcs_load_result = null; window.TWIWCS_DB.loadProject(function(d) { window._twiwcs_load_result = d; })")
	_poll_db_result("_twiwcs_load_result", _on_db_load_complete)


func _on_db_load_complete(json_str: String) -> void:
	print("[TWIWCS] _on_db_load_complete: ", json_str.substr(0, 500))
	var result = JSON.parse_string(json_str)
	if result == null or not result.get("success", false):
		var err_msg = result.get("error", "unknown") if result else "parse error"
		push_warning("[TWIWCS] Load failed: ", err_msg)
		_show_status("❌ Load failed: " + str(err_msg))
		return
	# Clear current scene
	_clear_scene()
	# Restore asset sets
	var assets_json = result.get("assets_json", "[]")
	print("[TWIWCS] assets_json length: ", assets_json.length())
	_deserialize_asset_sets(assets_json)
	# Restore placed sprites
	var layout_json = result.get("layout_json", "{}")
	print("[TWIWCS] layout_json length: ", layout_json.length())
	_deserialize_layout(layout_json)
	_has_saved_project = true
	print("[TWIWCS] Project loaded — sets: ", asset_sets.size(), " sprites: ", placed_sprites.size())
	_show_status("📂 Project loaded")


func _clear_scene() -> void:
	# Remove all placed sprites
	for sprite in placed_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	placed_sprites.clear()
	_selected_sprites.clear()
	undo_stack.clear()
	redo_stack.clear()
	_free_all_indicators()
	# Remove all asset set sections
	for child in asset_sections_container.get_children():
		child.queue_free()
	asset_sets.clear()
	_next_set_id = 0
	_set_count = 0
	active_asset_index = -1
	active_asset_texture = null


func _deserialize_asset_sets(data_json: String) -> void:
	var sets_data = JSON.parse_string(data_json)
	if sets_data == null or not (sets_data is Array):
		print("[TWIWCS] _deserialize_asset_sets: parse failed or not array — raw: ", data_json.substr(0, 300))
		return
	print("[TWIWCS] _deserialize_asset_sets: ", sets_data.size(), " entries")
	for entry in sets_data:
		_set_count += 1
		# Use the saved set_id so layout references match during deserialization.
		# Fall back to sequential (matches old behavior) if set_id wasn't stored.
		var set_id = entry.get("set_id", 0)
		if set_id == 0:
			set_id = _set_count
		if set_id > _next_set_id:
			_next_set_id = set_id
		var filename = entry.get("filename", "")
		print("[TWIWCS]   set_id=", set_id, " filename=", filename)
		var s = {
			"id": set_id,
			"png_path": filename,
			"json_path": entry.get("json_path", ""),
			"sheet_texture": null,
			"sheet_png_bytes": PackedByteArray(),
			"json_text": entry.get("json_metadata", ""),
			"frames": [],
			"textures": [],
			"section": _create_asset_section(set_id, _set_count),
		}
		# Decode PNG from base64
		var b64 = entry.get("png_base64", "")
		if b64 != "":
			var png_bytes = Marshalls.base64_to_raw(b64)
			if png_bytes.size() > 0:
				s["sheet_png_bytes"] = png_bytes
				var image := Image.new()
				if image.load_png_from_buffer(png_bytes) == OK:
					s["sheet_texture"] = ImageTexture.create_from_image(image)
					print("[TWIWCS]   PNG decoded OK: ", image.get_size())
				else:
					print("[TWIWCS]   PNG decode FAILED")
					push_warning("[TWIWCS] Failed to decode PNG for set ", set_id)
			else:
				print("[TWIWCS]   base64 decode produced empty bytes")
				push_warning("[TWIWCS] Empty PNG bytes for set ", set_id)
		else:
			print("[TWIWCS]   no png_base64 data")
			push_warning("[TWIWCS] No png_base64 for set ", set_id)
		# Append to asset_sets BEFORE parsing JSON so _find_set works
		asset_sets.append(s)
		# Parse JSON metadata
		var meta_text = entry.get("json_metadata", "")
		if meta_text != "":
			_parse_json_for_set(set_id, meta_text)
			print("[TWIWCS]   frames parsed: ", s["frames"].size())
		else:
			print("[TWIWCS]   no json_metadata")
		asset_sections_container.add_child(s["section"])
		_update_set_ui(set_id)
		_try_build_set(set_id)
	print("[TWIWCS] _deserialize_asset_sets done — total sets: ", asset_sets.size())


func _deserialize_layout(layout_json: String) -> void:
	print("[TWIWCS] _deserialize_layout: ", layout_json.substr(0, 300))
	var data = JSON.parse_string(layout_json)
	if data == null:
		print("[TWIWCS] _deserialize_layout: parse failed")
		return
	var objects = data.get("objects", [])
	for obj in objects:
		var set_id = obj.get("set_id", -1)
		var asset_id = obj.get("asset_id", "")
		var s = _find_set(set_id)
		if s.is_empty():
			continue
		# Find the matching texture by asset_id
		var tex: AtlasTexture = null
		for i in range(s["frames"].size()):
			if s["frames"][i]["filename"] == asset_id:
				if i < s["textures"].size():
					tex = s["textures"][i]
				break
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var pos = obj.get("position", {})
		sprite.position = Vector2(pos.get("x", 0), pos.get("y", 0))
		var sc = obj.get("scale", {})
		sprite.scale = Vector2(sc.get("x", 1.0), sc.get("y", 1.0))
		sprite.rotation_degrees = obj.get("rotation", 0.0)
		sprite.flip_h = obj.get("flip_h", false)
		sprite.z_index = obj.get("z_index", int(sprite.position.y) + 1000)
		sprite.set_meta("set_id", set_id)
		sprite.set_meta("asset_id", asset_id)
		sprite.set_meta("base_scale", Vector2(1.0, 1.0))
		sprite.set_meta("locked", obj.get("locked", false))
		asset_drop_zone.add_child(sprite)
		placed_sprites.append(sprite)


# ════════════════════════════════════════════════════════════
# Phase 7: .twiwcs Portable Backup
# ════════════════════════════════════════════════════════════

func _export_twiwcs() -> void:
	var layout_json = _serialize_layout()
	var assets_json = _serialize_asset_sets_for_save()
	# Build the .twiwcs package
	var package = {
		"twiwcs_version": "1.0",
		"layout": JSON.parse_string(layout_json),
		"asset_sets": JSON.parse_string(assets_json),
	}
	var package_json = JSON.stringify(package)
	var project_name = "project"
	if OS.has_feature("web"):
		if JavaScriptBridge:
			JavaScriptBridge.eval("window._twiwcs_exportdata = %s" % package_json)
			JavaScriptBridge.eval("""window.TWIWCS_DB.exportTwiwcs('%s', JSON.stringify(window._twiwcs_exportdata))""" % project_name.replace("'", "\\'"))
	else:
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.twiwcs;TWIWCS Backup"])
		dialog.file_selected.connect(func(path): _write_json_file(path, package_json); dialog.queue_free())
		dialog.canceled.connect(func(): dialog.queue_free())
		add_child(dialog)
		dialog.popup_centered(Vector2i(800, 600))


func _import_twiwcs() -> void:
	if not JavaScriptBridge:
		return
	JavaScriptBridge.eval("window._twiwcs_import_result = null; window.TWIWCS_DB.importTwiwcs(function(d) { window._twiwcs_import_result = d; })")
	_poll_db_result("_twiwcs_import_result", _on_twiwcs_import_complete)


func _on_twiwcs_import_complete(json_str: String) -> void:
	var raw = json_str
	if raw.begins_with("{") and raw.contains("success"):
		var err_result = JSON.parse_string(raw)
		if err_result and not err_result.get("success", true):
			push_warning("Import failed: ", err_result.get("error", "unknown"))
			return
	var package = JSON.parse_string(raw)
	if package == null:
		push_warning("Failed to parse .twiwcs file")
		return
	# Clear current scene
	_clear_scene()
	# Restore asset sets
	var asset_sets_data = package.get("asset_sets", [])
	_deserialize_asset_sets(JSON.stringify(asset_sets_data))
	# Restore layout
	var layout_data = package.get("layout", {})
	_deserialize_layout(JSON.stringify(layout_data))
	print("Import complete")
