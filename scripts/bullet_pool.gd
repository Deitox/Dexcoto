extends Node2D

@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@export var beam_scene: PackedScene = preload("res://scenes/Beam.tscn")

# Threshold after which projectiles turn into beams.
# Reduced by 100x to make the effect reachable in normal play.
const SPEED_BEAM_THRESHOLD: float = 900.0

var pool: Array = []
var _active_beams: Dictionary = {} # weapon_id -> Beam node

func _ready() -> void:
	add_to_group("bullet_pool")

func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, color: Color, lifetime: float = 2.0, effect: Dictionary = {}) -> Node:
	# If speed exceeds threshold, convert to a beam and scale damage by overflow.
	if speed > SPEED_BEAM_THRESHOLD and beam_scene:
		var overflow: float = speed / SPEED_BEAM_THRESHOLD
		var scaled_damage: int = int(round(float(damage) * overflow))
		# Channel a persistent beam per-weapon while beaming
		var key := "generic"
		if effect is Dictionary and effect.has("source") and effect["source"] is Dictionary:
			key = String(effect["source"].get("weapon_id", "generic"))
		# Derive DPS from current fire interval if available
		var interval: float = float(effect.get("fire_interval", 0.2))
		interval = max(0.02, interval)
		var dps: float = float(scaled_damage) / interval
		# Reuse an existing beam if present
		if _active_beams.has(key):
			var existing = _active_beams[key]
			if is_instance_valid(existing) and existing.has_method("channel"):
				existing.call("channel", pos, dir, dps, color, effect)
				return existing
			else:
				_active_beams.erase(key)
		var beam := beam_scene.instantiate()
		add_child(beam)
		if beam.has_method("activate_channel"):
			beam.call("activate_channel", pos, dir, dps, color, effect, key)
		_active_beams[key] = beam
		return beam
	# Otherwise spawn a pooled bullet, clamping speed to be safe.
	var effective_speed: float = min(speed, SPEED_BEAM_THRESHOLD)
	var b: Node = null
	if pool.size() > 0:
		b = pool.pop_back()
	else:
		b = bullet_scene.instantiate()
		add_child(b)
	if b.has_method("activate"):
		b.call("activate", pos, dir, effective_speed, damage, color, lifetime, self, effect)
	return b

func return_bullet(b: Node) -> void:
	if not is_instance_valid(b):
		return
	if b.has_method("deactivate"):
		b.call("deactivate")
	pool.append(b)

func get_beam_threshold() -> float:
	return SPEED_BEAM_THRESHOLD

func on_beam_freed(key: String) -> void:
	if _active_beams.has(key):
		_active_beams.erase(key)
