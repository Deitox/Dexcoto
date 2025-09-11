extends Node2D

@export var duration: float = 0.06
@export var width: float = 6.0
@export var max_length: float = 800.0
@export var color: Color = Color(1, 1, 0.6)

var _time := 0.0
var _active := false
var _damage: int = 0
var _effect: Dictionary = {}
var _channel := false
var _dps: float = 0.0
var _tick_accum: float = 0.0
var _tick_interval: float = 0.1
var _target: Node = null
var _beam_key: String = ""
var _aim_dir: Vector2 = Vector2.RIGHT
var _last_end_point: Vector2 = Vector2.ZERO
var _last_channel_time: float = 0.0
var _linger_after_no_target: float = 0.4
var _current_interval: float = 0.2

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
			var was_crit := false
			var player = get_tree().get_first_node_in_group("player")
			if player != null and player.has_method("compute_crit_result"):
				var res: Dictionary = player.compute_crit_result(final_damage)
				final_damage = int(res.get("damage", final_damage))
				was_crit = bool(res.get("crit", false))
			target.take_damage(final_damage)
			if target.has_method("show_damage_feedback"):
				target.show_damage_feedback(final_damage, was_crit, end_point)
			if _effect is Dictionary and _effect.size() > 0 and target.has_method("apply_elemental_effect"):
				target.apply_elemental_effect(_effect, final_damage, end_point)
	_set_line(Vector2.ZERO, (end_point - global_position))
	_last_end_point = end_point
	_time = 0.0
	_active = true
	visible = true

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _channel:
		# Update beam endpoint to current target position; if lost, end.
		var from_local: Vector2 = Vector2.ZERO
		if _target == null or not is_instance_valid(_target):
			# Try to retarget along last aim direction (cone + ray). Linger while shooter continues channeling.
			var ret: Array = _raycast_enemy(global_position, _aim_dir)
			var new_tgt: Node = null
			var endp: Vector2 = _last_end_point
			if ret.size() > 0:
				new_tgt = ret[0]
			if ret.size() > 1:
				endp = Vector2(ret[1])
			if new_tgt != null:
				_target = new_tgt
				_last_end_point = endp
			else:
				var now := float(Time.get_ticks_msec()) / 1000.0
				if now - _last_channel_time > _linger_after_no_target:
					_free_and_notify()
					return
		if _target != null and is_instance_valid(_target):
			var to_point: Vector2 = (_target.global_position - global_position)
			_set_line(from_local, to_point)
			visible = true
		else:
			# No valid target yet; hide beam to avoid apparent targeting of non-existent enemies
			visible = false
			return
		# Apply tick DPS
		_tick_accum += delta
		while _tick_accum >= _tick_interval:
			_tick_accum -= _tick_interval
			var tick_damage: int = max(1, int(round(_dps * _tick_interval)))
			if _target and _target.has_method("take_damage"):
				if _effect is Dictionary and _effect.has("source"):
					_target.set("last_damage_source", _effect["source"])
				var final_damage := tick_damage
				var player = get_tree().get_first_node_in_group("player")
				var was_crit := false
				if player != null and player.has_method("compute_crit_result"):
					var res: Dictionary = player.compute_crit_result(final_damage)
					final_damage = int(res.get("damage", final_damage))
					was_crit = bool(res.get("crit", false))
				_target.take_damage(final_damage)
				if _target and _target.has_method("show_damage_feedback"):
					_target.show_damage_feedback(final_damage, was_crit, _target.global_position)
				if _effect is Dictionary and _effect.size() > 0 and _target and _target.has_method("apply_elemental_effect"):
					_target.apply_elemental_effect(_effect, final_damage, _target.global_position)
				# If target died, end channel
				if not is_instance_valid(_target) or (_target.has_method("get") and int(_target.get("health")) <= 0):
					_free_and_notify()
					return
		return
	else:
		if _time >= duration:
			queue_free()

func _set_line(from_local: Vector2, to_point: Vector2) -> void:
	if not line:
		return
	line.clear_points()
	line.add_point(from_local)
	line.add_point(to_point)

# Persistent channel beams
func activate_channel(pos: Vector2, dir: Vector2, dps: float, col: Color, effect: Dictionary = {}, beam_key: String = "") -> void:
	global_position = pos
	_dps = max(0.0, dps)
	color = col
	_effect = effect if effect != null else {}
	_channel = true
	_beam_key = beam_key
	_aim_dir = dir.normalized()
	# Read current firing interval for linger heuristic
	if _effect is Dictionary and _effect.has("fire_interval"):
		_current_interval = max(0.02, float(_effect["fire_interval"]))
	_linger_after_no_target = clamp(_current_interval * 2.5, 0.3, 1.2)
	_last_channel_time = float(Time.get_ticks_msec()) / 1000.0
	if line:
		line.default_color = color
	var res := _raycast_enemy(pos, _aim_dir)
	var end_point: Vector2 = pos + _aim_dir * max_length
	if res.size() > 0:
		_target = res[0]
	if res.size() > 1:
		end_point = Vector2(res[1])
	_set_line(Vector2.ZERO, (end_point - global_position))
	_last_end_point = end_point
	_time = 0.0
	_active = true
	visible = true

func channel(pos: Vector2, _dir: Vector2, dps: float, col: Color, effect: Dictionary = {}) -> void:
	# Refresh channel: update dps and color; keep target if valid.
	global_position = pos
	_dps = max(_dps, dps)
	color = col
	_effect = effect if effect != null else _effect
	_aim_dir = _dir.normalized()
	# Update interval + last channel time for linger logic
	if _effect is Dictionary and _effect.has("fire_interval"):
		_current_interval = max(0.02, float(_effect["fire_interval"]))
	_linger_after_no_target = clamp(_current_interval * 2.5, 0.3, 1.2)
	_last_channel_time = float(Time.get_ticks_msec()) / 1000.0
	if line:
		line.default_color = color

func _free_and_notify() -> void:
	if _beam_key != "":
		var pool = get_tree().get_first_node_in_group("bullet_pool")
		if pool and pool.has_method("on_beam_freed"):
			pool.call("on_beam_freed", _beam_key)
	queue_free()

# Helper raycast to find first enemy along direction. Returns [target, end_point]
func _raycast_enemy(from_pos: Vector2, dir: Vector2) -> Array:
	# First, try a cone-based nearest-enemy search to avoid ghost colliders
	var cone_target := _find_enemy_in_cone(from_pos, dir, max_length, 12.0)
	if cone_target != null:
		return [cone_target, cone_target.global_position]
	# Fallback to physics ray stepping through hits
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var ndir: Vector2 = dir.normalized()
	var start: Vector2 = from_pos + ndir * 8.0
	var traveled: float = 0.0
	var last_end: Vector2 = start + ndir * max_length
	while traveled < max_length:
		var remain: float = max_length - traveled
		var to: Vector2 = start + ndir * remain
		var query := PhysicsRayQueryParameters2D.create(start, to)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = false
		var hit := space.intersect_ray(query)
		if not hit or not hit.has("position"):
			break
		var hit_pos: Vector2 = Vector2(hit["position"]) 
		last_end = hit_pos
		var collider = hit.get("collider")
		var target = collider
		if target and not target.is_in_group("enemies") and target.get_parent():
			var p = target.get_parent()
			if p and p.is_in_group("enemies"):
				target = p
		if target and target.is_in_group("enemies"):
			var ok := true
			if target.has_method("get"):
				var a = target.get("active")
				if a != null and not bool(a):
					ok = false
				var hp = target.get("health")
				if hp != null and int(hp) <= 0:
					ok = false
			if ok and target.is_visible_in_tree():
				return [target, hit_pos]
		# advance past this hit and continue
		start = hit_pos + ndir * 1.0
		traveled = (start - (from_pos + ndir * 8.0)).length()
	return [null, last_end]

# Search for the nearest valid enemy within a narrow cone along dir.
func _find_enemy_in_cone(from_pos: Vector2, dir: Vector2, max_dist: float, half_angle_deg: float) -> Node:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return null
	var ndir := dir.normalized()
	var cos_thresh := cos(deg_to_rad(half_angle_deg))
	var best: Node = null
	var best_score: float = -1.0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if not e.is_visible_in_tree():
			continue
		var ok := true
		if e.has_method("get"):
			var a = e.get("active")
			if a != null and not bool(a):
				ok = false
			var hp = e.get("health")
			if hp != null and int(hp) <= 0:
				ok = false
		if not ok:
			continue
		var v: Vector2 = e.global_position - from_pos
		var dist := v.length()
		if dist <= 0.001 or dist > max_dist:
			continue
		var dv := v / dist
		var dotv := ndir.dot(dv)
		if dotv < cos_thresh:
			continue
		# Favor alignment first, then proximity
		var score := dotv * 1000.0 - dist
		if score > best_score:
			best_score = score
			best = e
	return best
