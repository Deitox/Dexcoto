extends Node2D

@export var thickness: float = 32.0
@export var use_viewport_bounds: bool = false
@export var arena_size: Vector2 = Vector2(1024, 576) # used when not using viewport bounds

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

func _ensure_wall(name: String) -> void:
    if not has_node(name):
        var body := StaticBody2D.new()
        body.name = name
        add_child(body)
        var cs := CollisionShape2D.new()
        body.add_child(cs)
        cs.shape = RectangleShape2D.new()
    else:
        var body: Node = get_node(name)
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
