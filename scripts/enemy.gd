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
var last_damage_source: Dictionary = {}

@onready var hitbox: Area2D = $Hitbox
@onready var poly: Polygon2D = $Polygon2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Base color cache for tinting
var _base_poly_modulate: Color = Color(1,1,1,1)

# Elemental status effects
var ignite_time: float = 0.0
var ignite_dps: float = 0.0
var ignite_accum: float = 0.0
var freeze_time: float = 0.0
var void_time: float = 0.0
var void_vuln: float = 0.0

# FX nodes
var ignite_fx: Line2D = null
var void_aura: Line2D = null
var void_max_time: float = 0.0

const TIER_COLOR_PALETTE: Array[Color] = [
	Color(0.72, 0.58, 0.70), # muted lavender
	Color(0.48, 0.68, 0.72), # desaturated teal
	Color(0.56, 0.70, 0.55), # soft moss
	Color(0.70, 0.60, 0.44), # warm ochre
	Color(0.70, 0.50, 0.48), # brick rose
	Color(0.66, 0.52, 0.62), # plum haze
	Color(0.52, 0.62, 0.78), # calm steel blue
	Color(0.68, 0.64, 0.60)  # warm grey
]
const TIER_COLOR_VALUE_DROP: float = 0.05
const TIER_COLOR_SAT_BOOST: float = 0.04

func _ready() -> void:
	# Add to group only while active (done in activate()).
	_apply_tier()
	health = max_health
	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	if poly:
		_base_poly_modulate = poly.modulate

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
		hp = int(round(hp * 1.55))
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
		var tint := _color_for_tier(t)
		poly.modulate = tint
		_base_poly_modulate = tint

func _color_for_tier(t: int) -> Color:
	if TIER_COLOR_PALETTE.is_empty():
		return Color(1.0, 0.8, 0.35)
	var idx: int = int((t - 1) % TIER_COLOR_PALETTE.size())
	var cycle: int = int(floor(float(t - 1) / float(TIER_COLOR_PALETTE.size())))
	var base: Color = TIER_COLOR_PALETTE[idx]
	var h: float = base.h
	var s: float = clamp(base.s + TIER_COLOR_SAT_BOOST * float(cycle), 0.35, 1.0)
	var v: float = clamp(base.v - TIER_COLOR_VALUE_DROP * float(cycle), 0.45, 1.0)
	return Color.from_hsv(h, s, v, 1.0)


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
			# Burn DoT floating text (orange, slightly smaller)
			show_damage_feedback(tick, false, global_position, Color(1.0, 0.55, 0.2), 16)
	if freeze_time > 0.0:
		freeze_time = max(0.0, freeze_time - delta)
	if void_time > 0.0:
		void_time = max(0.0, void_time - delta)
	_update_status_visuals()
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
		# Inform player of kill with source attribution
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("on_enemy_killed"):
			player.call("on_enemy_killed", last_damage_source)
		_return_to_pool()

func _on_hitbox_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(contact_damage)

func activate(pos: Vector2, t: int, tgt: Node2D, p: Node) -> void:
	_reset_status_effects()
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
	last_damage_source = {}

func deactivate() -> void:
	active = false
	visible = false
	if is_in_group("enemies"):
		remove_from_group("enemies")
	if hitbox:
		hitbox.set_deferred("monitoring", false)
	if body_shape:
		body_shape.set_deferred("disabled", true)
	_reset_status_effects()

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
			var vd := float(effect.get("vuln_duration", 2.0))
			void_time = max(void_time, vd)
			void_max_time = max(void_max_time, vd)
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
				var arc_base: int = int(round(float(base_damage) * factor))
				var arc_dmg: int = arc_base
				var is_crit := false
				# Allow arcs to crit using the player's crit stats
				var player = get_tree().get_first_node_in_group("player")
				if player != null and player.has_method("compute_crit_result"):
					var res: Dictionary = player.compute_crit_result(arc_base)
					arc_dmg = int(res.get("damage", arc_base))
					is_crit = bool(res.get("crit", false))
				e.take_damage(arc_dmg)
				if e.has_method("show_damage_feedback"):
					e.show_damage_feedback(arc_dmg, is_crit, e.global_position)
				hits += 1
				_spawn_shock_arc(global_position, pos)

# Visual hit feedback: floating numbers + quick ring flash
func show_damage_feedback(amount: int, is_crit: bool, at: Vector2, custom_color: Color = Color(0,0,0,0), font_size: int = -1) -> void:
	# Floating number
	var label := Label.new()
	label.text = str(amount)
	var fsize := 24 if is_crit else 18
	if font_size > 0:
		fsize = font_size
	label.add_theme_font_size_override("font_size", fsize)
	var base_col := Color(1.0, 0.9, 0.2) if is_crit else Color(1,1,1)
	var use_col := base_col if custom_color.a <= 0.0 else custom_color
	label.add_theme_color_override("font_color", use_col)
	var parent := get_tree().current_scene
	if parent == null:
		return
	parent.add_child(label)
	label.global_position = at + Vector2(randf_range(-6,6), -8)
	label.z_index = 2000
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 16.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(label.queue_free)

func _ensure_ignite_fx() -> void:
	if ignite_fx != null and is_instance_valid(ignite_fx):
		return
	ignite_fx = Line2D.new()
	ignite_fx.width = 3.0
	ignite_fx.default_color = Color(1.0, 0.55, 0.2, 0.9)
	ignite_fx.z_index = 1200
	var pts := PackedVector2Array([
		Vector2(-6, 6), Vector2(0, -10), Vector2(6, 6), Vector2(0, -16), Vector2(-6, 6)
	])
	ignite_fx.points = pts
	add_child(ignite_fx)
	ignite_fx.position = Vector2.ZERO

func _clear_ignite_fx() -> void:
	if ignite_fx != null and is_instance_valid(ignite_fx):
		ignite_fx.queue_free()
	ignite_fx = null

func _ensure_void_aura() -> void:
	if void_aura != null and is_instance_valid(void_aura):
		return
	void_aura = Line2D.new()
	void_aura.width = 2.0
	void_aura.default_color = Color(0.8, 0.4, 1.0, 0.8)
	void_aura.z_index = 1100
	var r: float = 18.0 * scale.x
	var segs: int = 32
	var pts2 := PackedVector2Array()
	for s in range(segs + 1):
		var a := TAU * float(s) / float(segs)
		pts2.append(Vector2(cos(a), sin(a)) * r)
	void_aura.points = pts2
	add_child(void_aura)
	void_aura.position = Vector2.ZERO

func _clear_void_aura() -> void:
	if void_aura != null and is_instance_valid(void_aura):
		void_aura.queue_free()
	void_aura = null
	void_max_time = 0.0

func _reset_status_effects() -> void:
	ignite_time = 0.0
	ignite_dps = 0.0
	ignite_accum = 0.0
	freeze_time = 0.0
	void_time = 0.0
	void_vuln = 0.0
	void_max_time = 0.0
	last_damage_source = {}
	_clear_status_visuals()

func _spawn_shock_arc(from_pos: Vector2, to_pos: Vector2) -> void:
	var arc := Line2D.new()
	arc.width = 3.0
	arc.default_color = Color(0.6, 1.0, 1.0, 0.9)
	arc.z_index = 1300
	arc.points = PackedVector2Array([Vector2.ZERO, (to_pos - from_pos)])
	add_child(arc)
	arc.global_position = from_pos
	var tw := create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.2)
	tw.tween_callback(arc.queue_free)

func _update_status_visuals() -> void:
	# Freeze tint
	if poly:
		if freeze_time > 0.0:
			poly.modulate = Color(0.7, 0.85, 1.0, 1.0)
		else:
			poly.modulate = _base_poly_modulate
	# Ignite flames
	if ignite_time > 0.0:
		_ensure_ignite_fx()
		if ignite_fx:
			# simple pulse
			var t: float = sin(Time.get_ticks_msec() / 60.0) * 0.1 + 1.0
			ignite_fx.scale = Vector2(t, t)
	else:
		_clear_ignite_fx()
	# Void aura
	if void_time > 0.0:
		_ensure_void_aura()
		if void_aura and void_max_time > 0.0:
			var alpha: float = float(clamp(void_time / void_max_time, 0.0, 1.0))
			var c: Color = void_aura.default_color
			c.a = 0.2 + 0.6 * alpha
			void_aura.default_color = c
	else:
		_clear_void_aura()

func _clear_status_visuals() -> void:
	if poly:
		poly.modulate = _base_poly_modulate
	_clear_ignite_fx()
	_clear_void_aura()
