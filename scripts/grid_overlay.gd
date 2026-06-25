extends Node2D
## Isometric grid overlay — dynamically covers the entire visible viewport
## by calculating grid bounds from camera zoom and position.
## Redraws every frame so the grid follows camera pan/zoom.

const ISO_WIDTH := 600.0
const ISO_HEIGHT := 300.0
const GRID_DIVISIONS := 12
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const GRID_WIDTH := 1.0
const GRID_MAJOR_WIDTH := 3.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var vp_size := Vector2(get_viewport().size)
	var zoom: float = cam.zoom.x
	var cam_pos: Vector2 = cam.position

	# Visible world-space bounds (four corners)
	var half_vp := vp_size / (2.0 * zoom)
	var corners := [
		cam_pos + Vector2(-half_vp.x, -half_vp.y),
		cam_pos + Vector2( half_vp.x, -half_vp.y),
		cam_pos + Vector2(-half_vp.x,  half_vp.y),
		cam_pos + Vector2( half_vp.x,  half_vp.y),
	]

	var half_w: float = ISO_WIDTH / 2.0
	var half_h: float = ISO_HEIGHT / 2.0
	var top := Vector2(0.0, -half_h)

	var step_a := Vector2(half_w / GRID_DIVISIONS, half_h / GRID_DIVISIONS)
	var step_b := Vector2(-half_w / GRID_DIVISIONS, half_h / GRID_DIVISIONS)

	# Cramer's rule: project each corner onto grid axes (i, j)
	var det: float = step_a.x * step_b.y - step_b.x * step_a.y
	var i_min: float = INF
	var i_max: float = -INF
	var j_min: float = INF
	var j_max: float = -INF

	for c in corners:
		var dx: float = c.x - top.x
		var dy: float = c.y - top.y
		var i_val: float = (dx * step_b.y - dy * step_b.x) / det
		var j_val: float = (step_a.x * dy - step_a.y * dx) / det
		i_min = minf(i_min, i_val)
		i_max = maxf(i_max, i_val)
		j_min = minf(j_min, j_val)
		j_max = maxf(j_max, j_val)

	# Extend by 1 cell for safety margin, then floor/ceil to integers
	var i_lo: int = int(floorf(i_min)) - 1
	var i_hi: int = int(ceilf(i_max)) + 1
	var j_lo: int = int(floorf(j_min)) - 1
	var j_hi: int = int(ceilf(j_max)) + 1

	# A-lines (parallel to step_a, indexed by j along step_b)
	for j in range(j_lo, j_hi + 1):
		var origin := top + step_b * float(j)
		var p1 := origin + step_a * float(i_lo)
		var p2 := origin + step_a * float(i_hi)
		var w: float = GRID_MAJOR_WIDTH if j % 5 == 0 else GRID_WIDTH
		draw_line(p1, p2, GRID_COLOR, w)

	# B-lines (parallel to step_b, indexed by i along step_a)
	for i in range(i_lo, i_hi + 1):
		var origin := top + step_a * float(i)
		var p1 := origin + step_b * float(j_lo)
		var p2 := origin + step_b * float(j_hi)
		var w: float = GRID_MAJOR_WIDTH if i % 5 == 0 else GRID_WIDTH
		draw_line(p1, p2, GRID_COLOR, w)
