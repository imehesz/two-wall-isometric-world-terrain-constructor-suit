extends Control

## Main editor script — Phase 1: UI Framework & Canvas Setup
## Draws a two-wall isometric room (floor + back wall + left wall)
## and wires color pickers to the canvas and room surfaces.

@onready var sub_viewport: SubViewport = %SubViewport
@onready var canvas_panel: PanelContainer = %CanvasPanel
@onready var canvas_bg_color: ColorPickerButton = %CanvasBgColorPicker
@onready var room_color_picker: ColorPickerButton = %RoomColorPicker
@onready var floor_poly: Polygon2D = %FloorPolygon
@onready var wall_back_poly: Polygon2D = %WallBackPolygon
@onready var wall_left_poly: Polygon2D = %WallLeftPolygon
@onready var room_outline: Line2D = %RoomOutline
@onready var asset_drop_zone: Node2D = %AssetDropZone

## Isometric diamond dimensions (2:1 ratio)
const ISO_WIDTH := 600.0
const ISO_HEIGHT := 300.0
const WALL_HEIGHT := 200.0

## Default colors
const COLOR_BG := Color(0.12, 0.11, 0.14)
const COLOR_ROOM := Color(0.55, 0.65, 0.85)


func _ready() -> void:
	# Make SubViewport transparent so the CanvasPanel background shows through
	sub_viewport.transparent_bg = true

	# Apply initial colors
	_apply_bg_color(COLOR_BG)
	_apply_room_color(COLOR_ROOM)

	# Draw the room geometry
	_draw_room()

	# Fit camera after the viewport has its actual size
	call_deferred("_fit_camera")

	# Connect color pickers
	canvas_bg_color.color_changed.connect(_apply_bg_color)
	room_color_picker.color_changed.connect(_apply_room_color)


func _fit_camera() -> void:
	## Dynamically zoom the Camera2D so the room fills ~80% of the canvas.
	var vp_size := Vector2(sub_viewport.size)
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(800, 600)

	# Room bounding box: 600 wide, 650 tall (from Y=-500 to Y=150)
	var room_w := ISO_WIDTH           # 600
	var room_h := ISO_HEIGHT + WALL_HEIGHT  # 300 + 200 = 500 (floor half + wall)

	var zoom_x := vp_size.x * 0.8 / room_w
	var zoom_y := vp_size.y * 0.8 / room_h
	var zoom_val := minf(zoom_x, zoom_y)
	zoom_val = clampf(zoom_val, 0.3, 3.0)

	var cam := sub_viewport.get_node("Camera2D") as Camera2D
	cam.zoom = Vector2(zoom_val, zoom_val)
	# Center on the room: X=0, Y midpoint of (-500..150) = -175
	cam.position = Vector2(0.0, -175.0)


func _draw_room() -> void:
	var hw := ISO_WIDTH / 2.0
	var hh := ISO_HEIGHT / 2.0
	var wh := WALL_HEIGHT

	## Floor diamond (2:1 isometric)
	floor_poly.polygon = PackedVector2Array([
		Vector2(0.0, -hh),     # Top (back corner)
		Vector2(hw, 0.0),      # Right
		Vector2(0.0, hh),      # Bottom (front corner)
		Vector2(-hw, 0.0),     # Left
	])

	## Back wall — parallelogram rising from the Top→Right edge
	wall_back_poly.polygon = PackedVector2Array([
		Vector2(0.0, -hh),              # Bottom-left  (Top of diamond)
		Vector2(hw, 0.0),               # Bottom-right (Right of diamond)
		Vector2(hw, -hh - wh),          # Top-right
		Vector2(0.0, -hh - hh - wh),   # Top-left
	])

	## Left wall — parallelogram rising from the Left→Top edge
	wall_left_poly.polygon = PackedVector2Array([
		Vector2(-hw, 0.0),              # Bottom-left  (Left of diamond)
		Vector2(0.0, -hh),              # Bottom-right (Top of diamond)
		Vector2(0.0, -hh - hh - wh),   # Top-right
		Vector2(-hw, -hh - wh),         # Top-left
	])

	## Room outline — outer boundary of the visible room shape
	room_outline.clear_points()
	room_outline.add_point(Vector2(-hw, 0.0))             # Left
	room_outline.add_point(Vector2(0.0, -hh))             # Top
	room_outline.add_point(Vector2(0.0, -hh - hh - wh))  # Back wall top-left
	room_outline.add_point(Vector2(hw, -hh - wh))         # Back wall top-right
	room_outline.add_point(Vector2(hw, 0.0))              # Right
	room_outline.add_point(Vector2(0.0, hh))              # Bottom
	room_outline.add_point(Vector2(-hw, 0.0))             # Close


func _apply_bg_color(color: Color) -> void:
	## Change the CanvasPanel background via its StyleBoxFlat override
	var existing = canvas_panel.get_theme_stylebox("panel")
	var style: StyleBoxFlat
	if existing is StyleBoxFlat:
		style = existing.duplicate() as StyleBoxFlat
	else:
		style = StyleBoxFlat.new()
	style.bg_color = color
	canvas_panel.add_theme_stylebox_override("panel", style)


func _apply_room_color(color: Color) -> void:
	## Recolor the entire room — outline, floor, and both walls
	## deriving surface shades from the picked color.
	room_outline.default_color = color
	room_outline.width = 2.0

	var h := color.h
	var s := color.s
	var v := color.v

	# Floor: moderate brightness
	floor_poly.color = Color.from_hsv(h, s * 0.55, v * 0.45)
	# Back wall: darker (facing away from light)
	wall_back_poly.color = Color.from_hsv(h, s * 0.45, v * 0.35)
	# Left wall: darkest (in shadow)
	wall_left_poly.color = Color.from_hsv(h, s * 0.35, v * 0.28)
