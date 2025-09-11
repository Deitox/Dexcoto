extends Node2D

@export var duration: float = 0.06
@export var width: float = 6.0
@export var max_length: float = 800.0
@export var color: Color = Color(1, 1, 0.6)

var _time := 0.0
var _active := false
var _damage: int = 0
var _effect: Dictionary = {}

@onready var line: Line2D = $Line2D

func _ready() -> void:
	if line:
		line.width = width
		line.default_color = color

func activate(pos: Vector2, dir: Vector2, dmg: int, col: Color, effect: Dictionary = {}, length: float = -1.0) -> void:
	global_position = pos
	_damage = dmg
	color = col
	_effect = effect if effect != null else {}
	if line:
		line.default_color = color
	var beam_len: float = max_length if length <= 0.0 else length
	# Raycast to first collider to place beam end and apply damage.
	# Start slightly ahead to avoid originating inside the shooter/collider.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var ndir: Vector2 = dir.normalized()
	var from: Vector2 = pos + ndir * 8.0
	var to: Vector2 = from + ndir * beam_len
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	var end_point: Vector2 = to
	if hit and hit.has("position"):
		end_point = Vector2(hit["position"])
		var collider = hit.get("collider")
		var target = collider
		# If we hit a child like an enemy Hitbox (Area2D), resolve up to the enemy body.
		if target and not target.is_in_group("enemies") and target.get_parent():
			var p = target.get_parent()
			if p and p.is_in_group("enemies"):
				target = p
		if target and target.is_in_group("enemies") and target.has_method("take_damage"):
			# Attribute source for on-kill stacking
			if _effect is Dictionary and _effect.has("source"):
				target.set("last_damage_source", _effect["source"])
			var final_damage: int = _damage
			var player = get_tree().get_first_node_in_group("player")
			if player != null and player.has_method("compute_crit_damage"):
				final_damage = int(player.compute_crit_damage(final_damage))
			target.take_damage(final_damage)
			if _effect is Dictionary and _effect.size() > 0 and target.has_method("apply_elemental_effect"):
				target.apply_elemental_effect(_effect, final_damage, end_point)
	_set_line(Vector2.ZERO, (end_point - global_position))
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
