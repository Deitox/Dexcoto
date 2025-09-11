extends Area2D

@export var speed: float = 600.0
@export var lifetime: float = 2.0
@export var damage: int = 5
@export var color: Color = Color(1, 1, 0.2)

var direction: Vector2 = Vector2.RIGHT
var _life := 0.0

@onready var poly: Polygon2D = $Polygon2D
var active: bool = false
var pool: Node = null
var effect: Dictionary = {}

func _ready() -> void:
	# Join projectiles group only while active (done in activate()).
	body_entered.connect(_on_body_entered)
	if poly:
		poly.color = color

func _physics_process(delta: float) -> void:
	if not active:
		return
	global_position += direction * speed * delta
	_life += delta
	if _life > lifetime:
		_return_to_pool()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		var final_damage: int = damage
		var was_crit := false
		if body.has_method("take_damage"):
			# Attribute source for on-kill stacking effects
			if effect != null and effect is Dictionary and effect.has("source"):
				body.set("last_damage_source", effect["source"])
			var player_ref = get_tree().get_first_node_in_group("player")
			if player_ref != null and player_ref.has_method("compute_crit_result"):
				var res: Dictionary = player_ref.compute_crit_result(final_damage)
				final_damage = int(res.get("damage", final_damage))
				was_crit = bool(res.get("crit", false))
			body.take_damage(final_damage)
			if body.has_method("show_damage_feedback"):
				body.show_damage_feedback(final_damage, was_crit, global_position)
		# Apply elemental effect if supported (independent of explosion)
		var has_eff := (effect != null and effect is Dictionary and effect.size() > 0)
		if has_eff and body.has_method("apply_elemental_effect"):
			body.call("apply_elemental_effect", effect, final_damage, global_position)
		# Explosive AoE on hit
		if has_eff and bool(effect.get("explosive", false)):
			var radius: float = float(effect.get("radius", 120.0))
			var factor: float = float(effect.get("expl_factor", 0.9))
			var col: Color = Color(effect.get("color", Color(1,0.8,0.5)))
			var base_aoe: int = int(round(float(damage) * factor))
			var aoe_damage: int = base_aoe
			var player2 = get_tree().get_first_node_in_group("player")
			if player2 != null and player2.has_method("compute_crit_damage"):
				aoe_damage = int(player2.compute_crit_damage(base_aoe))
			_explode(global_position, aoe_damage, radius, col)
		# Cross-synergy items (player-driven)
		var player = get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("get_item_count"):
			var rolls: int = int(player.get_item_count("volatile_rounds"))
			if rolls > 0 and not bool(effect.get("explosive", false)):
				var chance: float = min(0.5, 0.08 * float(rolls))
				if randf() < chance:
					_explode(global_position, int(round(float(damage) * 0.7)), 100.0 + 20.0 * float(rolls), Color(1.0, 0.8, 0.5))
			var fuse: int = int(player.get_item_count("elemental_fuse"))
			if fuse > 0 and (effect == null or not effect.has("element")):
				var ch: float = min(0.6, 0.1 * float(fuse))
				if randf() < ch:
					_apply_random_elemental_to_target(body, final_damage if typeof(final_damage) == TYPE_INT else damage, fuse)
		_return_to_pool()

func _explode(pos: Vector2, dmg: int, radius: float, col: Color) -> void:
	# Damage nearby enemies and show a quick ring
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var r2: float = radius * radius
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d2: float = pos.distance_squared_to(e.global_position)
		if d2 <= r2 and e.has_method("take_damage"):
			# Attribute explosion to same source if present
			if effect != null and effect is Dictionary and effect.has("source"):
				e.set("last_damage_source", effect["source"])
			var final_dmg: int = dmg
			var was_crit2 := false
			var player_ref = get_tree().get_first_node_in_group("player")
			if player_ref != null and player_ref.has_method("compute_crit_result"):
				var res2: Dictionary = player_ref.compute_crit_result(final_dmg)
				final_dmg = int(res2.get("damage", final_dmg))
				was_crit2 = bool(res2.get("crit", false))
			e.take_damage(final_dmg)
			if e.has_method("show_damage_feedback"):
				e.show_damage_feedback(final_dmg, was_crit2, e.global_position)
	# Visual polish: double shockwave + radial streaks
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = col
	var segs: int = 32
	var pts := PackedVector2Array()
	for s in range(segs + 1):
		var a := TAU * float(s) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	get_tree().current_scene.add_child(ring)
	ring.global_position = pos
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.28)
	tw.tween_callback(ring.queue_free)
	# Inner ring expands slightly
	var ring2 := Line2D.new()
	ring2.width = 2.0
	ring2.default_color = Color(col.r, col.g, col.b, 0.85)
	var pts2 := PackedVector2Array()
	for s in range(segs + 1):
		var a2 := TAU * float(s) / float(segs)
		pts2.append(Vector2(cos(a2), sin(a2)) * (radius * 0.6))
	ring2.points = pts2
	get_tree().current_scene.add_child(ring2)
	ring2.global_position = pos
	var tw2 := ring2.create_tween()
	tw2.tween_property(ring2, "scale", Vector2(1.3, 1.3), 0.22)
	tw2.tween_property(ring2, "modulate:a", 0.0, 0.22)
	tw2.tween_callback(ring2.queue_free)
	# Radial streaks
	var rays: int = 8
	for i in range(rays):
		var ang := TAU * float(i) / float(rays)
		var ray := Line2D.new()
		ray.width = 2.0
		ray.default_color = Color(col.r, col.g, col.b, 0.9)
		ray.points = PackedVector2Array([Vector2.ZERO, Vector2(cos(ang), sin(ang)) * (radius * 0.9)])
		get_tree().current_scene.add_child(ray)
		ray.global_position = pos
		var twr := ray.create_tween()
		twr.tween_property(ray, "modulate:a", 0.0, 0.18)
		twr.tween_callback(ray.queue_free)
	# Payload Catalyst: apply elemental proc to AoE victims
	var player_items = get_tree().get_first_node_in_group("player")
	if player_items != null and player_items.has_method("get_item_count"):
		var payload: int = int(player_items.get_item_count("payload_catalyst"))
		if payload > 0:
			var chance: float = min(0.5, 0.1 * float(payload))
			for e2 in enemies:
				if not is_instance_valid(e2):
					continue
				var d22: float = pos.distance_squared_to(e2.global_position)
				if d22 <= r2 and e2.has_method("apply_elemental_effect") and randf() < chance:
					var ef := _random_element_effect(payload)
					e2.apply_elemental_effect(ef, dmg, e2.global_position)

func _apply_random_elemental_to_target(target: Node, base_damage: int, power_scale: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var elems: Array[String] = ["fire","cryo","shock","void"]
	var pick: String = elems[randi() % elems.size()]
	var eff: Dictionary = {"element": pick, "proc": 1.0, "power": 1.0 + 0.2 * float(power_scale)}
	match pick:
		"fire":
			eff["ignite_factor"] = 0.35
			eff["ignite_duration"] = 1.6
		"cryo":
			eff["freeze_duration"] = 0.8
		"shock":
			eff["arc_count"] = 2 + power_scale
			eff["arc_radius"] = 120.0 + 10.0 * float(power_scale)
			eff["arc_factor"] = 0.45
		"void":
			eff["vuln"] = 0.15
			eff["vuln_duration"] = 2.0
		_:
			pass
	if target.has_method("apply_elemental_effect"):
		target.apply_elemental_effect(eff, base_damage, target.global_position)

func _random_element_effect(power_scale: int) -> Dictionary:
	var elems: Array[String] = ["fire","cryo","shock","void"]
	var pick: String = elems[randi() % elems.size()]
	var eff: Dictionary = {"element": pick, "proc": 1.0, "power": 1.0 + 0.2 * float(power_scale)}
	match pick:
		"fire":
			eff["ignite_factor"] = 0.3
			eff["ignite_duration"] = 1.4
		"cryo":
			eff["freeze_duration"] = 0.7
		"shock":
			eff["arc_count"] = 2 + power_scale
			eff["arc_radius"] = 120.0 + 10.0 * float(power_scale)
			eff["arc_factor"] = 0.4
		"void":
			eff["vuln"] = 0.15
			eff["vuln_duration"] = 1.8
		_:
			pass
	return eff

func activate(pos: Vector2, dir: Vector2, spd: float, dmg: int, col: Color, life: float, p: Node, eff: Dictionary = {}) -> void:
	global_position = pos
	direction = dir
	speed = spd
	damage = dmg
	color = col
	lifetime = life
	_life = 0.0
	active = true
	pool = p
	effect = eff if eff != null else {}
	visible = true
	set_deferred("monitoring", true)
	if not is_in_group("projectiles"):
		add_to_group("projectiles")
	if poly:
		poly.color = color

func deactivate() -> void:
	active = false
	visible = false
	set_deferred("monitoring", false)
	if is_in_group("projectiles"):
		remove_from_group("projectiles")

func _return_to_pool() -> void:
	if pool and pool.has_method("return_bullet"):
		pool.call("return_bullet", self)
	else:
		queue_free()
