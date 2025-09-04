extends CharacterBody2D

@export var move_speed: float = 120.0
@export var max_health: int = 20
@export var contact_damage: int = 10

var health: int
var target: Node2D
var tier: int = 1
var active: bool = true
var pool: Node = null
var reward_points: int = 1

@onready var hitbox: Area2D = $Hitbox
@onready var poly: Polygon2D = $Polygon2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Elemental status effects
var ignite_time: float = 0.0
var ignite_dps: float = 0.0
var ignite_accum: float = 0.0
var freeze_time: float = 0.0
var void_time: float = 0.0
var void_vuln: float = 0.0

func _ready() -> void:
	# Add to group only while active (done in activate()).
	_apply_tier()
	health = max_health
	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)

func set_tier(t: int) -> void:
	tier = max(1, t)
	_apply_tier()
	health = max_health

func _apply_tier() -> void:
	var t: int = max(1, tier)
	var base_hp: int = 20
	var base_dmg: int = 10
	var base_speed: float = 120.0
	var hp: int = base_hp
	var dmg: int = base_dmg
	var spd: float = base_speed
	for i in range(2, t + 1):
		hp = int(round(hp * 1.5))
		dmg = int(round(dmg * 1.25))
		spd *= 0.95
	max_health = hp
	contact_damage = dmg
	move_speed = spd
	# Compute reward points roughly proportional to enemy power.
	# Base is 1 at tier 1; scales mostly with HP, slightly with damage.
	var hp_factor: float = float(max_health) / 20.0
	var dmg_factor: float = float(contact_damage) / 10.0
	reward_points = max(1, int(round(hp_factor * 0.8 + dmg_factor * 0.2)))
	var s: float = 1.0 + 0.15 * float(t - 1)
	scale = Vector2(s, s)
	if poly:
		poly.color = Color(1.0, 0.3 + 0.1 * float(t - 1), 0.3)


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var delta := _delta
	# Elemental DoT / debuffs
	if ignite_time > 0.0:
		ignite_time = max(0.0, ignite_time - delta)
		ignite_accum += ignite_dps * delta
		var tick := int(ignite_accum)
		if tick > 0:
			ignite_accum -= float(tick)
			take_damage(tick)
	if freeze_time > 0.0:
		freeze_time = max(0.0, freeze_time - delta)
	if void_time > 0.0:
		void_time = max(0.0, void_time - delta)
	if target == null or not is_instance_valid(target):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
		else:
			return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	# If frozen, do not move
	if freeze_time > 0.0:
		velocity = Vector2.ZERO
	else:
		velocity = dir * move_speed
	move_and_slide()

func take_damage(amount: int) -> void:
	var amt := amount
	if void_time > 0.0 and void_vuln > 0.0:
		amt = int(round(float(amt) * (1.0 + void_vuln)))
	health -= amt
	if health <= 0:
		if get_tree().current_scene and get_tree().current_scene.has_method("add_score"):
			# Pass 1 kill and reward points scaled to enemy power
			get_tree().current_scene.add_score(1, reward_points)
		_return_to_pool()

func _on_hitbox_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(contact_damage)

func activate(pos: Vector2, t: int, tgt: Node2D, p: Node) -> void:
	global_position = pos
	set_tier(t)
	target = tgt
	pool = p
	active = true
	if not is_in_group("enemies"):
		add_to_group("enemies")
	visible = true
	modulate.a = 1.0
	if hitbox:
		hitbox.set_deferred("monitoring", true)
	if body_shape:
		body_shape.set_deferred("disabled", false)
	if poly:
		poly.visible = true

func deactivate() -> void:
	active = false
	visible = false
	if is_in_group("enemies"):
		remove_from_group("enemies")
	if hitbox:
		hitbox.set_deferred("monitoring", false)
	if body_shape:
		body_shape.set_deferred("disabled", true)
	ignite_time = 0.0
	ignite_dps = 0.0
	ignite_accum = 0.0
	freeze_time = 0.0
	void_time = 0.0
	void_vuln = 0.0

func _return_to_pool() -> void:
	if pool and pool.has_method("return_enemy"):
		pool.call("return_enemy", self)
	else:
		queue_free()

func apply_elemental_effect(effect: Dictionary, hit_damage: int, _hit_pos: Vector2) -> void:
	if effect == null or not (effect is Dictionary):
		return
	var elem: String = String(effect.get("element", ""))
	var proc: float = float(effect.get("proc", 0.0))
	if randf() > proc:
		return
	var power: float = float(effect.get("power", 1.0))
	match elem:
		"fire":
			var factor: float = float(effect.get("ignite_factor", 0.4)) * power
			var dur: float = float(effect.get("ignite_duration", 2.0))
			ignite_dps = max(ignite_dps, float(int(round(float(hit_damage) * factor))))
			ignite_time = max(ignite_time, dur)
		"cryo":
			var fdur: float = float(effect.get("freeze_duration", 0.8)) * clamp(power, 1.0, 2.0)
			freeze_time = max(freeze_time, fdur)
		"shock":
			var count: int = int(effect.get("arc_count", 2))
			var radius: float = float(effect.get("arc_radius", 140.0))
			var factor2: float = float(effect.get("arc_factor", 0.5)) * power
			_apply_shock_arcs(hit_damage, count, radius, factor2)
		"void":
			void_vuln = max(void_vuln, float(effect.get("vuln", 0.2)) * power)
			void_time = max(void_time, float(effect.get("vuln_duration", 2.0)))
		_:
			pass

func _apply_shock_arcs(base_damage: int, count: int, radius: float, factor: float) -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var hits := 0
	for e in enemies:
		if hits >= count:
			break
		if e == self or not is_instance_valid(e):
			continue
		if not e.is_visible_in_tree():
			continue
		var pos: Vector2 = e.global_position
		if global_position.distance_to(pos) <= radius:
			if e.has_method("take_damage"):
				e.take_damage(int(round(float(base_damage) * factor)))
				hits += 1
