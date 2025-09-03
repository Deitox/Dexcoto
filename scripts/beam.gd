extends Node2D

@export var duration: float = 0.06
@export var width: float = 6.0
@export var max_length: float = 800.0
@export var color: Color = Color(1, 1, 0.6)

var _time := 0.0
var _active := false
var _damage: int = 0

@onready var line: Line2D = $Line2D

func _ready() -> void:
	if line:
		line.width = width
		line.default_color = color

func activate(pos: Vector2, dir: Vector2, dmg: int, col: Color, length: float = -1.0) -> void:
	global_position = pos
	_damage = dmg
	color = col
	if line:
		line.default_color = color
	var beam_len: float = max_length if length <= 0.0 else length
	# Raycast to first collider to place beam end and apply damage.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var to: Vector2 = pos + dir.normalized() * beam_len
	var query := PhysicsRayQueryParameters2D.create(pos, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	var end_point: Vector2 = to
	if hit and hit.has("position"):
		end_point = Vector2(hit["position"])
		var collider = hit.get("collider")
		if collider and collider.is_in_group("enemies") and collider.has_method("take_damage"):
			collider.take_damage(_damage)
	_set_line(Vector2.ZERO, (end_point - pos))
	_time = 0.0
	_active = true
	visible = true

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _time >= duration:
		queue_free()

func _set_line(from_local: Vector2, to_point: Vector2) -> void:
	if not line:
		return
	line.clear_points()
	line.add_point(from_local)
	line.add_point(to_point)
