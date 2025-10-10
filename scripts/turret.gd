extends Node2D

@export var fire_interval: float = 0.8
@export var damage: int = 6
@export var speed: float = 480.0
@export var attack_range: float = 420.0
@export var color: Color = Color(0.7, 1.0, 0.3)

var tier: int = 1
var _cd: float = 0.0
@onready var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@onready var bullet_pool: Node = null
var active: bool = true
var pool: Node = null
var turret_role: String = "attack"
var heal_amount: int = 6
var healing_aura: Line2D = null
var aura_time: float = 0.0

# Performance caps
const MIN_TURRET_INTERVAL: float = 0.12
const HEALING_AURA_RADIUS: float = 20.0
const HEALING_AURA_SEGMENTS: int = 32

func _color_for_tier(t: int) -> Color:
	match t:
		1:
			return Color(0.85, 0.85, 0.85)
		2:
			return Color(0.4, 1.0, 0.4)
		3:
			return Color(0.4, 0.6, 1.0)
		4:
			return Color(0.8, 0.4, 1.0)
		5:
			return Color(1.0, 0.7, 0.2)
		6:
			return Color(1.0, 0.3, 0.3) # Mythic
		7:
			return Color(0.2, 1.0, 1.0) # Celestial
		8:
			return Color(1.0, 0.3, 0.8) # Arcane
		9:
			return Color(0.6, 1.0, 0.2) # Radiant
		10:
			return Color(1.0, 1.0, 1.0) # Transcendent
		_:
			return Color(1,1,1)

func _ready() -> void:
	# Add to group only while active (in activate()).
	_apply_tier()
	bullet_pool = get_tree().get_first_node_in_group("bullet_pool")

func set_tier(t: int) -> void:
	tier = max(1, t)
	_apply_tier()

func _apply_tier() -> void:
	# Scale stats by tier: similar to weapons
	var t: int = max(1, tier)
	var base_fire: float = 0.8
	var base_damage: int = 6
	var base_speed: float = 480.0
	var base_range: float = 420.0
	var fi: float = base_fire
	var dmg: int = base_damage
	var proj_speed: float = base_speed
	var rng: float = base_range
	for i in range(2, t + 1):
		dmg = int(round(dmg * 1.25))
		fi *= 0.9
		rng *= 1.05
	fire_interval = fi
	damage = dmg
	speed = proj_speed
	attack_range = rng
	if turret_role == "healing":
		heal_amount = max(2, int(round(float(dmg) * 0.6)))
	# Make turret slightly larger per tier
	var s: float = 1.0 + 0.1 * float(t - 1)
	scale = Vector2(s, s)
	# Color by tier
	var poly: Polygon2D = $Polygon2D if has_node("Polygon2D") else null
	if poly:
		if turret_role == "healing":
			poly.color = Color(0.5, 1.0, 0.8)
		else:
			poly.color = _color_for_tier(t)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if turret_role == "healing":
		aura_time += delta
		_update_healing_aura()
		_cd -= delta
		if _cd <= 0.0:
			var healed := _heal_player()
			if healed:
				_cd = max(MIN_TURRET_INTERVAL, fire_interval)
			else:
				_cd = max(MIN_TURRET_INTERVAL, fire_interval * 0.5)
		return
	_cd -= delta
	if _cd <= 0.0:
		var target: Node2D = _get_nearest_enemy_in_range()
		if target:
			_shoot(target.global_position)
			_cd = max(MIN_TURRET_INTERVAL, fire_interval)

func _get_nearest_enemy_in_range() -> Node2D:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_d: float = attack_range * attack_range
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var is_active := true
		if e.has_method("get"):
			var a = e.get("active")
			if a != null:
				is_active = bool(a)
		if not is_active or not e.is_visible_in_tree():
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < min_d:
			min_d = d
			nearest = e
	return nearest

func _shoot(pos: Vector2) -> void:
	if turret_role == "healing":
		return
	var dir: Vector2 = (pos - global_position).normalized()
	# Projectiles overload control
	var current: int = get_tree().get_nodes_in_group("projectiles").size()
	var soft_cap: int = 200
	var scale_factor: float = 1.0
	if current > soft_cap:
		scale_factor = clamp(float(soft_cap) / float(current), 0.3, 1.0)
	var dmg := int(round(damage * (1.0 / scale_factor)))
	# Scale by player's turret power stat if present
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get"):
		var tpm: float = float(player.get("turret_power_mult"))
		if tpm > 0.0:
			dmg = int(round(float(dmg) * max(0.1, tpm)))
	var spd_to_use: float = speed
	if player and player.has_method("get"):
		var tpsm: float = float(player.get("turret_projectile_speed_mult"))
		if tpsm > 0.0:
			spd_to_use = speed * tpsm
	var fx: Dictionary = {"source": {"kind":"turret", "weapon_id": "turret_%d" % get_instance_id()}}
	if bullet_pool and bullet_pool.has_method("spawn_bullet"):
		# Provide current fire interval for beam DPS estimate
		fx["fire_interval"] = float(fire_interval)
		fx["shooter_path"] = get_path()
		bullet_pool.call("spawn_bullet", global_position + dir * 16.0, dir, spd_to_use, dmg, color, 2.0, fx)
	else:
		var b = bullet_scene.instantiate()
		get_tree().current_scene.add_child(b)
		if b.has_method("activate"):
			b.call("activate", global_position + dir * 16.0, dir, spd_to_use, dmg, color, 2.0, null, fx)
		else:
			b.global_position = global_position + dir * 16.0
			b.direction = dir
			b.speed = spd_to_use
			b.damage = dmg
			b.color = color

func _heal_player() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("heal"):
		return false
	var heal_mult: float = 1.0
	if player.has_method("get"):
		var overflow_v = player.get("overflow_healing_mult_from_defense")
		if overflow_v != null:
			heal_mult *= max(0.1, float(overflow_v))
		var turret_power_v = player.get("turret_power_mult")
		if turret_power_v != null:
			heal_mult *= max(0.1, float(turret_power_v))
	var amount: int = int(round(float(heal_amount) * heal_mult))
	if amount <= 0:
		return false
	var actual: int = int(player.call("heal", amount))
	if actual <= 0:
		return false
	_emit_heal_fx(actual)
	return true

func _emit_heal_fx(amount: int) -> void:
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.8))
	label.modulate = Color(1, 1, 1, 0.0)
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(label)
	label.global_position = global_position + Vector2(0, -18)
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(label, "position:y", label.position.y - 16.0, 0.3)
	tw.tween_property(label, "modulate:a", 0.0, 0.2)
	tw.tween_callback(label.queue_free)

	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(0.5, 1.0, 0.8, 0.6)
	var pts := PackedVector2Array()
	for i in range(HEALING_AURA_SEGMENTS + 1):
		var angle := TAU * float(i) / float(HEALING_AURA_SEGMENTS)
		pts.append(Vector2(cos(angle), sin(angle)) * (HEALING_AURA_RADIUS * 0.8))
	ring.points = pts
	add_child(ring)
	ring.z_index = -1
	ring.modulate = Color(1, 1, 1, 0.6)
	ring.scale = Vector2.ONE
	var tw_ring := ring.create_tween()
	tw_ring.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_ring.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	tw_ring.tween_callback(ring.queue_free)

func _ensure_healing_aura() -> void:
	if healing_aura != null and is_instance_valid(healing_aura):
		healing_aura.visible = true
		return
	healing_aura = Line2D.new()
	healing_aura.width = 3.0
	healing_aura.default_color = Color(0.4, 1.0, 0.8, 0.6)
	var pts := PackedVector2Array()
	for i in range(HEALING_AURA_SEGMENTS + 1):
		var angle := TAU * float(i) / float(HEALING_AURA_SEGMENTS)
		pts.append(Vector2(cos(angle), sin(angle)) * HEALING_AURA_RADIUS)
	healing_aura.points = pts
	healing_aura.z_index = -1
	healing_aura.modulate = Color(1, 1, 1, 0.5)
	add_child(healing_aura)

func _hide_healing_aura() -> void:
	if healing_aura != null and is_instance_valid(healing_aura):
		healing_aura.visible = false
	aura_time = 0.0

func _update_healing_aura() -> void:
	if healing_aura == null or not is_instance_valid(healing_aura):
		return
	var pulse_scale: float = 1.0 + 0.08 * sin(aura_time * 4.0)
	var alpha: float = 0.3 + 0.15 * (0.5 + 0.5 * sin(aura_time * 3.0))
	healing_aura.scale = Vector2(pulse_scale, pulse_scale)
	var col := healing_aura.modulate
	col.a = clamp(alpha, 0.0, 1.0)
	healing_aura.modulate = col

func activate(pos: Vector2, t: int, p: Node, mode := "attack") -> void:
	turret_role = String(mode)
	global_position = pos
	pool = p
	active = true
	if not is_in_group("turrets"):
		add_to_group("turrets")
	if turret_role == "healing":
		if not is_in_group("healing_turrets"):
			add_to_group("healing_turrets")
		_ensure_healing_aura()
		aura_time = 0.0
	else:
		if is_in_group("healing_turrets"):
			remove_from_group("healing_turrets")
		_hide_healing_aura()
	set_tier(t)
	_cd = 0.0
	visible = true

func deactivate() -> void:
	active = false
	visible = false
	if is_in_group("turrets"):
		remove_from_group("turrets")
	if is_in_group("healing_turrets"):
		remove_from_group("healing_turrets")
	turret_role = "attack"
	heal_amount = 6
	_cd = 0.0
	_hide_healing_aura()
	pool = null
