extends Node2D

@export var thickness: float = 32.0
@export var use_viewport_bounds: bool = false
@export var arena_size: Vector2 = Vector2(1024, 576) # used when not using viewport bounds
@export var outline_visible: bool = true
@export var outline_color: Color = Color(1, 1, 1, 0.35)
@export var outline_width: float = 2.0

var rect_origin: Vector2 = Vector2.ZERO
var rect_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Ensure 4 walls exist
	_ensure_wall("Top")
	_ensure_wall("Bottom")
	_ensure_wall("Left")
	_ensure_wall("Right")
	# Size initially and on resize
	_update_walls()
	if get_viewport():
		get_viewport().size_changed.connect(_update_walls)
	_ensure_outline()
	_update_outline()

func _ensure_wall(body_name: String) -> void:
	if not has_node(body_name):
		var body := StaticBody2D.new()
		body.name = body_name
		add_child(body)
		var cs := CollisionShape2D.new()
		body.add_child(cs)
		cs.shape = RectangleShape2D.new()
	else:
		var body: Node = get_node(body_name)
		if not body.has_node("CollisionShape2D"):
			var cs := CollisionShape2D.new()
			body.add_child(cs)
			cs.shape = RectangleShape2D.new()

func _update_walls() -> void:
	var rect := get_viewport().get_visible_rect()
	var sx: float
	var sy: float
	var origin: Vector2
	if use_viewport_bounds:
		sx = rect.size.x
		sy = rect.size.y
		origin = rect.position
	else:
		sx = arena_size.x
		sy = arena_size.y
		# Center the arena at this node's global position
		origin = global_position - Vector2(sx, sy) * 0.5
	var t: float = max(1.0, thickness)

	rect_origin = origin
	rect_size = Vector2(sx, sy)

	# Top and bottom span width; left and right span height
	# Use centers positioned just outside the screen so inner edge aligns with viewport edge
	_set_wall(
		"Top",
		Vector2(origin.x + sx * 0.5, origin.y - t * 0.5),
		Vector2(sx + t * 2.0, t)
	)
	_set_wall(
		"Bottom",
		Vector2(origin.x + sx * 0.5, origin.y + sy + t * 0.5),
		Vector2(sx + t * 2.0, t)
	)
	_set_wall(
		"Left",
		Vector2(origin.x - t * 0.5, origin.y + sy * 0.5),
		Vector2(t, sy + t * 2.0)
	)
	_set_wall(
		"Right",
		Vector2(origin.x + sx + t * 0.5, origin.y + sy * 0.5),
		Vector2(t, sy + t * 2.0)
	)
	_update_outline()

func _set_wall(body_name: String, pos: Vector2, size: Vector2) -> void:
	if not has_node(body_name):
		return
	var body: Node2D = get_node(body_name)
	body.global_position = pos
	var cs: CollisionShape2D = body.get_node_or_null("CollisionShape2D")
	if cs == null:
		cs = CollisionShape2D.new()
		body.add_child(cs)
	var r := cs.shape as RectangleShape2D
	if r == null:
		r = RectangleShape2D.new()
		cs.shape = r
	r.size = size

func _ensure_outline() -> void:
	var line := get_node_or_null("Outline") as Line2D
	if line == null:
		line = Line2D.new()
		line.name = "Outline"
		add_child(line)
	line.default_color = outline_color
	line.width = outline_width
	line.visible = outline_visible
	line.z_index = 1000

func _update_outline() -> void:
	var line := get_node_or_null("Outline") as Line2D
	if line == null:
		return
	line.visible = outline_visible
	line.default_color = outline_color
	line.width = outline_width
	# position outline at top-left of arena rect and set points locally
	line.global_position = rect_origin
	var sx: float = rect_size.x
	var sy: float = rect_size.y
	var pts := PackedVector2Array([
		Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sy), Vector2(0, sy), Vector2(0, 0)
	])
	line.points = pts

func get_arena_rect() -> Rect2:
	return Rect2(rect_origin, rect_size)
