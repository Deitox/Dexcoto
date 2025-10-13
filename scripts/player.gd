extends CharacterBody2D

@export var move_speed: float = 240.0
@export var max_health: int = 100
@export var fire_interval: float = 0.35
@export var bullet_speed: float = 500.0
@export var bullet_damage: int = 10

var health: int
var _regen_accum: float = 0.0

# Upgradable/global stats
var regen_per_second: float = 0.0
var projectiles_per_shot: int = 0 # extra projectiles added to each weapon's base
var spread_degrees: float = 14.0
var input_enabled: bool = true
var currency_gain_mult: float = 1.0
var attack_speed_mult: float = 1.0
var damage_mult: float = 1.0
var projectile_speed_mult: float = 1.0
var bullet_color: Color = Color(1, 1, 0.2)
var lifesteal_per_kill: int = 0
@onready var body_poly: Polygon2D = $Polygon2D

# Critical hits
var crit_chance: float = 0.0 # 0.0 = 0%, 1.0 = 100%. Overflow >1.0 boosts crit damage.
var crit_damage_mult: float = 1.5 # Damage multiplier applied on critical hits

# Defense (incoming damage multiplier; <1.0 reduces damage taken)
var incoming_damage_mult: float = 1.0

# Elemental scaling (affects elemental weapons only)
var elemental_damage_mult: float = 1.0
var explosive_power_mult: float = 1.0
var turret_power_mult: float = 1.0
var turret_projectile_speed_mult: float = 1.0

# Item ownership counts (by item id)
var item_counts: Dictionary = {}

# Track bonus damage gained from exceeding caps
var overflow_damage_mult_from_attack_speed: float = 1.0
var overflow_damage_mult_from_projectiles: float = 1.0
var overflow_currency_mult_from_move_speed: float = 1.0
var overflow_healing_mult_from_defense: float = 1.0
var heartforge_damage_bonus_applied: float = 1.0
var heartforge_attack_bonus_applied: float = 1.0
var titan_barrier: int = 0
var titan_barrier_max: int = 0
var hemorrhage_lifesteal_gain_per_kill: int = 0
var hemorrhage_shockwave_damage: int = 0
var hemorrhage_shockwave_radius: float = 0.0
var _hemorrhage_shockwave_triggers: int = 0
var _hemorrhage_shockwave_processing: bool = false

# Debug/guard against rare teleport glitches
var _last_pos: Vector2 = Vector2.ZERO
var _teleport_log_cooldown: float = 0.0

# Weapon system
const MAX_WEAPON_SLOTS: int = 6
var weapons: Array[Dictionary] = [] # each: {id, name, tier, fire_interval, damage, speed, projectiles, color, cd}
var _kill_counters: Dictionary = {} # weapon_id -> kills toward next stack

@onready var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@onready var bullet_pool: Node = null

signal died
signal weapon_added(index: int)
signal weapon_merged(id: String, tier: int, index: int)

# Performance caps
const MAX_TOTAL_PROJECTILES: int = 10
const MAX_PROJECTILE_BONUS: int = 10 # cap on player.projectiles_per_shot
const MAX_ATTACK_SPEED_MULT: float = 4.0
const MIN_WEAPON_INTERVAL: float = 0.08
const MAX_MOVE_SPEED_MULT: float = 3.0
const MIN_INCOMING_DAMAGE_MULT: float = 0.20
const TITAN_WARD_BARRIER_RATIO: float = 0.15
const HEMORRHAGE_SHOCKWAVE_BASE_RADIUS: float = 160.0
const HEMORRHAGE_SHOCKWAVE_DURATION: float = 0.35

var base_move_speed: float = 0.0

var _transform_change_allowed: bool = false
var _last_transform_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_ensure_default_input_actions()
	health = max_health
	bullet_pool = get_tree().get_first_node_in_group("bullet_pool")
	# Ensure we pick up the pool if its _ready adds the group after ours runs
	call_deferred("_ensure_bullet_pool")
	_last_pos = global_position
	# Record base speed for cap calculations
	base_move_speed = move_speed
	set_notify_transform(true)
	_last_transform_position = global_position
	notify_max_health_changed()

func set_position_and_reset_guard(pos: Vector2) -> void:
	# Public helper to intentionally reposition the player without triggering the anti-teleport guard.
	_transform_change_allowed = true
	global_position = pos
	_transform_change_allowed = false
	_last_pos = pos
	velocity = Vector2.ZERO
	_last_transform_position = global_position


func _physics_process(delta: float) -> void:
	# Regen
	if regen_per_second > 0.0 and health > 0:
		_regen_accum += regen_per_second * delta
		var heal_amount: int = int(_regen_accum)
		if heal_amount > 0:
			_regen_accum -= float(heal_amount)
			heal(heal_amount)

	var input_dir: Vector2 = Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_dir * move_speed
	_transform_change_allowed = true
	move_and_slide()
	_transform_change_allowed = false

	# Anti-teleport guard: if we moved an unexpectedly large distance in one physics frame,
	# cancel the move and zero velocity. This is defensive while we hunt the root cause.
	var step_dist: float = global_position.distance_to(_last_pos)
	var expected_step: float = move_speed * delta * 2.5 # generous factor for diagonals/buffs
	var hard_cap: float = 960.0 # absolute threshold in px/frame (guard against genuine teleports)
	if step_dist > max(expected_step, hard_cap):
		var attempted_pos: Vector2 = global_position
		var prev_pos: Vector2 = _last_pos
		_transform_change_allowed = true
		global_position = _last_pos
		_transform_change_allowed = false
		velocity = Vector2.ZERO
		if _teleport_log_cooldown <= 0.0:
			_log_guard_event(step_dist, expected_step, hard_cap, delta, attempted_pos, prev_pos)
			_teleport_log_cooldown = 1.0
	_teleport_log_cooldown = max(0.0, _teleport_log_cooldown - delta)
	_last_pos = global_position
	_last_transform_position = global_position

	var target: Node2D = _get_nearest_enemy()
	if target:
		_update_weapons_fire(delta, target.global_position)

func _get_nearest_enemy() -> Node2D:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var min_d: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		# Skip pooled/inactive or hidden enemies
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

func _ensure_default_input_actions() -> void:
	var defaults: Dictionary = {
		"ui_left": {
			"keys": [Key.KEY_LEFT, Key.KEY_A],
			"buttons": [JOY_BUTTON_DPAD_LEFT],
			"motions": [{ "axis": JOY_AXIS_LEFT_X, "value": -1.0 }],
		},
		"ui_right": {
			"keys": [Key.KEY_RIGHT, Key.KEY_D],
			"buttons": [JOY_BUTTON_DPAD_RIGHT],
			"motions": [{ "axis": JOY_AXIS_LEFT_X, "value": 1.0 }],
		},
		"ui_up": {
			"keys": [Key.KEY_UP, Key.KEY_W],
			"buttons": [JOY_BUTTON_DPAD_UP],
			"motions": [{ "axis": JOY_AXIS_LEFT_Y, "value": -1.0 }],
		},
		"ui_down": {
			"keys": [Key.KEY_DOWN, Key.KEY_S],
			"buttons": [JOY_BUTTON_DPAD_DOWN],
			"motions": [{ "axis": JOY_AXIS_LEFT_Y, "value": 1.0 }],
		},
		"ui_cancel": {
			"keys": [Key.KEY_ESCAPE],
			"buttons": [JOY_BUTTON_START],
			"motions": [],
		},
		"ui_accept": {
			"keys": [Key.KEY_ENTER, Key.KEY_KP_ENTER, Key.KEY_SPACE],
			"buttons": [JOY_BUTTON_A],
			"motions": [],
		},
	}
	for action in defaults.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var cfg: Dictionary = defaults.get(action, {})
		var key_list: Array = cfg.get("keys", [])
		for key in key_list:
			var keycode: int = int(key)
			if not _action_has_physical_key(action, keycode):
				var ev := InputEventKey.new()
				var key_enum: Key = keycode as Key
				ev.physical_keycode = key_enum
				ev.keycode = key_enum
				InputMap.action_add_event(action, ev)
		var button_list: Array = cfg.get("buttons", [])
		for button in button_list:
			var button_index: int = int(button)
			if not _action_has_joy_button(action, button_index):
				var btn_ev := InputEventJoypadButton.new()
				btn_ev.button_index = button_index as JoyButton
				InputMap.action_add_event(action, btn_ev)
		var motion_list: Array = cfg.get("motions", [])
		for motion_variant in motion_list:
			if typeof(motion_variant) != TYPE_DICTIONARY:
				continue
			var motion: Dictionary = motion_variant
			var axis: int = int(motion.get("axis", 0))
			var value: float = float(motion.get("value", 0.0))
			if not _action_has_joy_axis(action, axis, value):
				var motion_ev := InputEventJoypadMotion.new()
				motion_ev.axis = axis as JoyAxis
				motion_ev.axis_value = value
				InputMap.action_add_event(action, motion_ev)

func _action_has_physical_key(action: String, key: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var event := e as InputEventKey
			if event.physical_keycode == key or event.keycode == key:
				return true
	return false

func _action_has_joy_button(action: String, button: int) -> bool:
	var button_enum: JoyButton = button as JoyButton
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button_enum:
			return true
	return false

func _action_has_joy_axis(action: String, axis: int, value: float) -> bool:
	var axis_enum: JoyAxis = axis as JoyAxis
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			var event := e as InputEventJoypadMotion
			if event.axis == axis_enum and is_equal_approx(event.axis_value, value):
				return true
	return false

func _update_weapons_fire(delta: float, target_pos: Vector2) -> void:
	for i in range(weapons.size()):
		var w: Dictionary = weapons[i]
		w["cd"] = float(w.get("cd", 0.0)) - delta
		if w["cd"] <= 0.0:
			_fire_weapon_at(w, target_pos)
			var base_cd: float = float(w["fire_interval"]) / max(0.1, attack_speed_mult)
			w["cd"] = max(MIN_WEAPON_INTERVAL, base_cd)
		weapons[i] = w

func _fire_weapon_at(w: Dictionary, pos: Vector2) -> void:
	var dir: Vector2 = (pos - global_position).normalized()
	var base_proj: int = int(w.get("projectiles", 1))
	var shots: int = max(1, base_proj + projectiles_per_shot)
	var dmg: int = int(round(int(w.get("damage", 10)) * damage_mult))
	var spd: float = float(w.get("speed", 500.0)) * projectile_speed_mult
	var color: Color = Color(w.get("color", bullet_color))
	# Elemental scaling and effect packaging
	var effect: Dictionary = {}
	if w.has("element"):
		dmg = int(round(float(dmg) * elemental_damage_mult))
		var elem: String = String(w.get("element"))
		var base_proc: float = float(w.get("element_proc", 0.0))
		var final_proc: float = clamp(base_proc * elemental_damage_mult, 0.0, 0.95)
		effect = {
			"element": elem,
			"proc": final_proc,
			"power": elemental_damage_mult,
		}
		var keys := [
			"ignite_factor","ignite_duration",
			"freeze_duration",
			"arc_count","arc_radius","arc_factor",
			"vuln","vuln_duration"
		]
		for k in keys:
			if w.has(k):
				effect[k] = w[k]
		# Superconductor synergy boosts Shock arcs
		if elem == "shock" and has_method("get_item_count"):
			var sc: int = int(get_item_count("superconductor"))
			if sc > 0:
				effect["arc_count"] = int(effect.get("arc_count", 2)) + sc
				effect["arc_radius"] = float(effect.get("arc_radius", 140.0)) + 12.0 * float(sc)
	# Explosive packaging (AoE on hit)
	if bool(w.get("explosive", false)):
		if effect.size() == 0:
			effect = {}
		effect["explosive"] = true
		var base_r: float = float(w.get("expl_radius", 120.0))
		effect["radius"] = base_r * max(0.1, explosive_power_mult)
		effect["expl_factor"] = float(w.get("expl_factor", 0.9)) * max(0.5, explosive_power_mult)
		effect["color"] = color
	# Attach source attribution for on-kill stacking effects
	effect["source"] = {"kind":"weapon", "weapon_id": String(w.get("id","")), "tier": int(w.get("tier",1))}
	# Include current fire interval after attack speed so beams can estimate DPS
	var current_interval: float = float(w.get("fire_interval", 0.4)) / max(0.1, attack_speed_mult)
	effect["fire_interval"] = current_interval
	# Provide shooter path so beams can attach to the firing node
	effect["shooter_path"] = get_path()
	# Cap total projectiles and convert overflow into proportional damage
	if shots > MAX_TOTAL_PROJECTILES:
		var scale_up: float = float(shots) / float(MAX_TOTAL_PROJECTILES)
		shots = MAX_TOTAL_PROJECTILES
		dmg = int(round(float(dmg) * scale_up))
	# Projectiles overload control
	var current: int = get_tree().get_nodes_in_group("projectiles").size()
	var soft_cap: int = 200
	if current > soft_cap:
		var scale_factor: float = clamp(float(soft_cap) / float(current), 0.3, 1.0)
		shots = max(1, int(round(float(shots) * scale_factor)))
		dmg = int(round(float(dmg) * (1.0 / scale_factor)))
	if shots == 1:
		_ensure_bullet_pool()
		if bullet_pool and bullet_pool.has_method("spawn_bullet"):
			bullet_pool.call("spawn_bullet", global_position + dir * 16.0, dir, spd, dmg, color, 2.0, effect)
		else:
			var b = bullet_scene.instantiate()
			get_tree().current_scene.add_child(b)
			if b.has_method("activate"):
				b.call("activate", global_position + dir * 16.0, dir, spd, dmg, color, 2.0, null, effect)
			else:
				b.global_position = global_position + dir * 16.0
				b.direction = dir
				b.speed = spd
				b.damage = dmg
				b.color = color
	else:
		var total_spread: float = deg_to_rad(spread_degrees)
		var start_angle: float = -total_spread * 0.5
		var step: float = 0.0
		if shots > 1:
			step = total_spread / float(shots - 1)
		for i in range(shots):
			var angle: float = start_angle + step * i
			var d: Vector2 = dir.rotated(angle)
			_ensure_bullet_pool()
			if bullet_pool and bullet_pool.has_method("spawn_bullet"):
				bullet_pool.call("spawn_bullet", global_position + d * 16.0, d, spd, dmg, color, 2.0, effect)
			else:
				var b2 = bullet_scene.instantiate()
				get_tree().current_scene.add_child(b2)
				if b2.has_method("activate"):
					b2.call("activate", global_position + d * 16.0, d, spd, dmg, color, 2.0, null, effect)
				else:
					b2.global_position = global_position + d * 16.0
					b2.direction = d
					b2.speed = spd
					b2.damage = dmg
					b2.color = color

func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return
	var final: int = int(max(1, round(float(amount) * max(0.05, incoming_damage_mult))))
	final = _apply_titan_ward_barrier_to_damage(final)
	if final <= 0:
		return
	health -= final
	if health <= 0:
		health = 0
		emit_signal("died")

func heal(amount: int) -> int:
	if amount <= 0 or health <= 0:
		return 0
	var missing: int = max(0, max_health - health)
	var healed: int = min(missing, amount)
	if healed > 0:
		health += healed
	var overflow: int = amount - healed
	if overflow > 0:
		_titan_ward_convert_overheal(overflow)
	return healed

func notify_max_health_changed() -> void:
	_on_max_health_changed()

func _on_max_health_changed() -> void:
	health = min(health, max_health)
	_recalc_heartforge_core_bonus()
	_update_titan_ward_barrier_cap()
	_recalc_hemorrhage_engine_values()

func _recalc_heartforge_core_bonus() -> void:
	if heartforge_damage_bonus_applied != 1.0:
		damage_mult /= heartforge_damage_bonus_applied
	if heartforge_attack_bonus_applied != 1.0:
		attack_speed_mult /= heartforge_attack_bonus_applied
	heartforge_damage_bonus_applied = 1.0
	heartforge_attack_bonus_applied = 1.0
	var count: int = get_item_count("heartforge_core")
	if count <= 0:
		return
	var stacks: int = int(floor(float(max_health) / 25.0))
	if stacks <= 0:
		return
	var dmg_bonus: float = pow(1.0 + 0.03 * float(count), float(stacks))
	var atk_bonus: float = pow(1.0 + 0.01 * float(count), float(stacks))
	heartforge_damage_bonus_applied = max(0.0001, dmg_bonus)
	heartforge_attack_bonus_applied = max(0.0001, atk_bonus)
	damage_mult *= heartforge_damage_bonus_applied
	attack_speed_mult *= heartforge_attack_bonus_applied

func _update_titan_ward_barrier_cap() -> void:
	var count: int = get_item_count("titan_ward")
	if count <= 0:
		titan_barrier_max = 0
		titan_barrier = 0
		return
	var cap: int = int(round(float(max_health) * TITAN_WARD_BARRIER_RATIO * float(count)))
	titan_barrier_max = max(0, cap)
	titan_barrier = clamp(titan_barrier, 0, titan_barrier_max)

func _titan_ward_convert_overheal(amount: int) -> void:
	if amount <= 0 or titan_barrier_max <= 0:
		return
	var space: int = max(0, titan_barrier_max - titan_barrier)
	if space <= 0:
		return
	var add: int = min(space, amount)
	titan_barrier += add

func _apply_titan_ward_barrier_to_damage(amount: int) -> int:
	if amount <= 0 or titan_barrier <= 0 or titan_barrier_max <= 0:
		return amount
	var absorb: int = min(titan_barrier, amount)
	titan_barrier -= absorb
	return amount - absorb

func refresh_titan_ward_barrier() -> void:
	if titan_barrier_max > 0:
		titan_barrier = titan_barrier_max

func get_titan_ward_barrier() -> Dictionary:
	return {
		"current": titan_barrier,
		"max": titan_barrier_max,
	}

func _recalc_hemorrhage_engine_values() -> void:
	var count: int = get_item_count("hemorrhage_engine")
	if count <= 0:
		hemorrhage_lifesteal_gain_per_kill = 0
		hemorrhage_shockwave_damage = 0
		hemorrhage_shockwave_radius = 0.0
		_hemorrhage_shockwave_triggers = 0
		_hemorrhage_shockwave_processing = false
		return
	var lifesteal_gain: int = int(floor(float(max_health) / 40.0)) * count
	hemorrhage_lifesteal_gain_per_kill = max(0, lifesteal_gain)
	var dmg: int = int(round(float(max_health) * 0.06 * float(count)))
	hemorrhage_shockwave_damage = max(0, dmg)
	hemorrhage_shockwave_radius = HEMORRHAGE_SHOCKWAVE_BASE_RADIUS + 20.0 * float(max(0, count - 1))

func _queue_hemorrhage_shockwave() -> void:
	if hemorrhage_shockwave_damage <= 0:
		return
	_hemorrhage_shockwave_triggers += 1
	if not _hemorrhage_shockwave_processing:
		_hemorrhage_shockwave_processing = true
		call_deferred("_process_hemorrhage_shockwaves")

func _process_hemorrhage_shockwaves() -> void:
	while _hemorrhage_shockwave_triggers > 0 and hemorrhage_shockwave_damage > 0:
		_hemorrhage_shockwave_triggers -= 1
		_emit_hemorrhage_shockwave(hemorrhage_shockwave_damage)
	_hemorrhage_shockwave_processing = false
	if hemorrhage_shockwave_damage <= 0:
		_hemorrhage_shockwave_triggers = 0

func _emit_hemorrhage_shockwave(damage: int) -> void:
	if damage <= 0:
		return
	var radius: float = hemorrhage_shockwave_radius if hemorrhage_shockwave_radius > 0.0 else HEMORRHAGE_SHOCKWAVE_BASE_RADIUS
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var enemy := e as Node2D
		if enemy == null:
			continue
		if not enemy.has_method("take_damage"):
			continue
		var dist: float = enemy.global_position.distance_to(global_position)
		if dist > radius:
			continue
		enemy.set("last_damage_source", {"kind":"item", "item_id":"hemorrhage_engine"})
		enemy.call("take_damage", damage)
	_spawn_hemorrhage_shockwave_visual(radius)

func _spawn_hemorrhage_shockwave_visual(radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 6.0
	ring.default_color = Color(0.85, 0.2, 0.4)
	var segs: int = 32
	var pts := PackedVector2Array()
	for s in range(segs + 1):
		var angle := TAU * float(s) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	ring.points = pts
	add_child(ring)
	ring.position = Vector2.ZERO
	ring.z_index = 5
	var tw := create_tween()
	if tw:
		tw.tween_property(ring, "width", 0.5, HEMORRHAGE_SHOCKWAVE_DURATION)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, HEMORRHAGE_SHOCKWAVE_DURATION)
		tw.tween_callback(Callable(ring, "queue_free"))
	else:
		ring.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var current_pos := global_position
		if not _transform_change_allowed:
			var delta := current_pos.distance_to(_last_transform_position)
			if delta > 48.0:
				print("[TransformGuard] Unexpected transform change: ", delta, " px")
				var stack := get_stack()
				for entry in stack:
					print("    ", str(entry))
		_last_transform_position = current_pos

# Compute final damage after rolling crits.
# - Crit chance is capped at 100% for the roll; overflow above 1.0 increases crit damage multiplier additively.
# - Returns an int scaled from base_damage.
func compute_crit_result(base_damage: int) -> Dictionary:
	# Returns {"damage": int, "crit": bool}
	var dmg: float = float(base_damage)
	var chance: float = max(0.0, crit_chance)
	var overflow: float = 0.0
	if chance > 1.0:
		overflow = chance - 1.0
		chance = 1.0
	var effective_mult: float = crit_damage_mult + overflow
	var is_crit: bool = randf() < chance
	if is_crit:
		dmg *= max(1.0, effective_mult)
	return {"damage": int(round(dmg)), "crit": is_crit}

func compute_crit_damage(base_damage: int) -> int:
	# Back-compat helper used where crit flag not needed
	var res := compute_crit_result(base_damage)
	return int(res.get("damage", base_damage))

func apply_upgrade(upg: Dictionary) -> void:
	var t: String = String(upg.get("type", ""))
	var v: Variant = upg.get("value")
	match t:
		"attack_speed":
			apply_attack_speed_multiplier(1.0 + float(v))
		"damage":
			damage_mult *= (1.0 + float(v))
		"move_speed":
			apply_move_speed_multiplier(1.0 + float(v))
		"max_hp":
			max_health += int(v)
			notify_max_health_changed()
			heal(int(v))
		"bullet_speed":
			projectile_speed_mult *= (1.0 + float(v))
		"regen":
			regen_per_second += float(v)
		"defense":
			# Reduce incoming damage by value (e.g., 0.10 => 10% less damage taken)
			apply_incoming_damage_multiplier(1.0 - float(v))
		"projectiles":
			var add: int = int(v)
			for i in range(add):
				if projectiles_per_shot < MAX_PROJECTILE_BONUS:
					projectiles_per_shot += 1
				else:
					# Convert surplus projectile into ~10% damage (approx equal to going from 10->11 projectiles)
					damage_mult *= 1.1
					overflow_damage_mult_from_projectiles *= 1.1
		"elemental_power":
			elemental_damage_mult *= (1.0 + float(v))
		"explosive_power":
			explosive_power_mult *= (1.0 + float(v))
		"turret_power":
			turret_power_mult *= (1.0 + float(v))
		_:
			pass

# Applies a multiplicative change to incoming damage, respecting the minimum clamp.
func apply_incoming_damage_multiplier(mult: float) -> void:
	var m: float = max(0.0, mult)
	incoming_damage_mult *= m
	incoming_damage_mult = max(MIN_INCOMING_DAMAGE_MULT, incoming_damage_mult)

# Applies a multiplicative change to move speed with a 3x cap.
# Overflow beyond 3x converts to Currency Gain multiplier.
func apply_move_speed_multiplier(mult: float) -> void:
	var m = max(0.0, mult)
	var cap_speed: float = max(1.0, base_move_speed) * MAX_MOVE_SPEED_MULT
	move_speed = move_speed * m
	if move_speed > cap_speed:
		var overflow_factor: float = move_speed / cap_speed
		move_speed = cap_speed
		var of = max(1.0, overflow_factor)
		currency_gain_mult *= of
		overflow_currency_mult_from_move_speed *= of

# Applies a multiplicative change to attack speed with a cap.
# Overflow beyond cap converts into Damage multiplier and tracked overflow.
func apply_attack_speed_multiplier(mult: float) -> void:
	var m = max(0.0, mult)
	attack_speed_mult *= m
	if attack_speed_mult > MAX_ATTACK_SPEED_MULT:
		var overflow_factor: float = attack_speed_mult / MAX_ATTACK_SPEED_MULT
		attack_speed_mult = MAX_ATTACK_SPEED_MULT
		damage_mult *= overflow_factor
		overflow_damage_mult_from_attack_speed *= overflow_factor

func can_accept_weapon(w: Dictionary) -> bool:
	if String(w.get("kind", "")) != "weapon":
		return false
	var id: String = String(w.get("id", ""))
	var tier: int = int(w.get("tier", 1))
	# Always accept if we have a free slot
	if weapons.size() < MAX_WEAPON_SLOTS:
		return true
	# Only accept when full if this purchase enables an immediate merge
	var count_same_tier: int = 0
	for ww in weapons:
		if String(ww.get("id", "")) == id and int(ww.get("tier", 1)) == tier:
			count_same_tier += 1
	return count_same_tier >= 2

func equip_weapon(w: Dictionary) -> void:
	if String(w.get("kind", "")) != "weapon":
		return
	var start_tier: int = int(w.get("tier", 1))
	var inst: Dictionary = {
		"id": String(w.get("id")),
		"name": String(w.get("name")),
		"tier": start_tier,
		"fire_interval": float(w.get("fire_interval", 0.4)),
		"damage": int(w.get("damage", 8)),
		"speed": float(w.get("speed", 500.0)),
		"projectiles": int(w.get("projectiles", 1)),
		"color": w.get("color", Color(1,1,0.2)),
		"cd": 0.0,
	}
	# Copy optional elemental fields if present
	var opt_keys := [
		"element","element_proc",
		"ignite_factor","ignite_duration",
		"freeze_duration",
		"arc_count","arc_radius","arc_factor",
		"vuln","vuln_duration",
		"stack"
	]
	for k in opt_keys:
		if w.has(k):
			inst[k] = w[k]
	# Copy explosive fields if present
	if bool(w.get("explosive", false)):
		inst["explosive"] = true
		if w.has("expl_radius"):
			inst["expl_radius"] = w["expl_radius"]
		if w.has("expl_factor"):
			inst["expl_factor"] = w["expl_factor"]
	# Apply tier scaling if starting above tier 1
	if start_tier > 1:
		for t in range(2, start_tier + 1):
			inst["damage"] = int(round(int(inst["damage"]) * 1.25))
			inst["fire_interval"] = float(inst["fire_interval"]) * 0.9
			if t % 3 == 0:
				inst["projectiles"] = int(inst["projectiles"]) + 2
	weapons.append(inst)
	var added_index: int = weapons.size() - 1
	var merge_info: Dictionary = _try_merge_weapon(String(inst["id"]))
	if bool(merge_info.get("merged", false)):
		var idx: int = int(merge_info.get("index", weapons.size() - 1))
		var new_tier: int = int(merge_info.get("new_tier", 1))
		emit_signal("weapon_merged", String(inst["id"]), new_tier, idx)
	else:
		emit_signal("weapon_added", added_index)

func set_player_color(c: Color) -> void:
	bullet_color = c
	if body_poly:
		body_poly.color = c

func add_item(id: String) -> void:
	var cur: int = int(item_counts.get(id, 0))
	item_counts[id] = cur + 1

func get_item_count(id: String) -> int:
	return int(item_counts.get(id, 0))

func _try_merge_weapon(id: String) -> Dictionary:
	# Merge three of same id and same tier into one higher tier. Repeat while possible.
	var merged: bool = true
	var any_merged: bool = false
	var final_index: int = -1
	var final_tier: int = 0
	while merged:
		merged = false
		# group indices by tier
		var by_tier: Dictionary = {}
		for i in range(weapons.size()):
			var w: Dictionary = weapons[i]
			if String(w.get("id","")) != id:
				continue
			var t: int = int(w.get("tier",1))
			if not by_tier.has(t):
				by_tier[t] = []
			by_tier[t].append(i)
		# find any tier with 3 or more
		for tier in by_tier.keys():
			var arr: Array = by_tier[tier]
			if arr.size() >= 3:
				# remove three highest indices to avoid shifting earlier
				arr.sort() # ascending
				var idxs: Array = []
				var n: int = arr.size()
				idxs.append(arr[n-1])
				idxs.append(arr[n-2])
				idxs.append(arr[n-3])
				idxs.sort() # ascending for safe removal
				# base stats from one of them
				var base: Dictionary = weapons[idxs[-1]]
				# remove from weapons
				for j in range(idxs.size()):
					var rem_index: int = int(idxs[j])
					weapons.remove_at(rem_index)
					# adjust other indices > rem_index in all arr entries
					for k in range(j+1, idxs.size()):
						if int(idxs[k]) > rem_index:
							idxs[k] = int(idxs[k]) - 1
				# create upgraded weapon
				var new_tier: int = int(tier) + 1
				var new_inst: Dictionary = base.duplicate(true)
				new_inst["tier"] = new_tier
				# scale stats
				new_inst["damage"] = int(round(int(new_inst["damage"]) * 1.25))
				new_inst["fire_interval"] = float(new_inst["fire_interval"]) * 0.9
				if new_tier % 3 == 0:
					new_inst["projectiles"] = int(new_inst["projectiles"]) + 2
				new_inst["cd"] = 0.0
				weapons.append(new_inst)
				any_merged = true
				final_index = weapons.size() - 1
				final_tier = new_tier
				merged = true
				break
		# loop again if merged
	return {
		"merged": any_merged,
		"index": final_index,
		"new_tier": final_tier,
	}

func on_enemy_killed(source: Dictionary) -> void:
	if source == null or not (source is Dictionary):
		return
	var kind: String = String(source.get("kind",""))
	if kind == "weapon":
		var wid: String = String(source.get("weapon_id",""))
		if wid != "":
			# Find the matching weapon instance to read its stack config and tier
			var picked: Dictionary = {}
			for w in weapons:
				if String(w.get("id","")) == wid:
					picked = w
					break
			if not picked.is_empty() and picked.has("stack"):
				var sconf: Dictionary = picked["stack"]
				var base_kills: int = int(sconf.get("base_kills", 5))
				var tier: int = int(picked.get("tier", 1))
				# Higher tier requires fewer kills: divide by (1 + 0.25*(tier-1))
				var denom: float = 1.0 + 0.25 * float(max(0, tier - 1))
				var need: int = max(1, int(round(float(base_kills) / denom)))
				var cur: int = int(_kill_counters.get(wid, 0)) + 1
				if cur >= need:
					_kill_counters[wid] = 0
					_apply_stack_effect(String(sconf.get("type","")), sconf, picked)
				else:
					_kill_counters[wid] = cur
	_apply_item_kill_effects()

func _apply_item_kill_effects() -> void:
	var hem_count: int = get_item_count("hemorrhage_engine")
	if hem_count <= 0 or max_health <= 0 or health <= 0:
		return
	var ratio: float = float(health) / float(max_health)
	if ratio < 0.75:
		return
	if hemorrhage_shockwave_damage > 0:
		_queue_hemorrhage_shockwave()
	if hemorrhage_lifesteal_gain_per_kill > 0:
		lifesteal_per_kill += hemorrhage_lifesteal_gain_per_kill

func _apply_stack_effect(stype: String, conf: Dictionary, source_weapon: Dictionary = {}) -> void:
	var weapon_id: String = String(source_weapon.get("id", ""))
	var weapon_tier: int = int(source_weapon.get("tier", 1))
	match stype:
		"damage":
			var inc: float = float(conf.get("per_stack", 0.02))
			damage_mult *= (1.0 + inc)
			_show_stack_cue("+%d%% Damage" % int(round(inc*100.0)), Color(1.0,0.5,0.5))
		"attack_speed":
			var inc2: float = float(conf.get("per_stack", 0.02))
			apply_attack_speed_multiplier(1.0 + inc2)
			_show_stack_cue("+%d%% Attack Speed" % int(round(inc2*100.0)), Color(0.6,1.0,0.6))
		"projectile_speed":
			var inc_ps: float = float(conf.get("per_stack", 0.05))
			projectile_speed_mult *= (1.0 + inc_ps)
			_show_stack_cue("+%d%% Proj Speed" % int(round(inc_ps*100.0)), Color(0.6,0.9,1.0))
		"move_speed":
			var inc_ms: float = float(conf.get("per_stack", 0.02))
			apply_move_speed_multiplier(1.0 + inc_ms)
			_show_stack_cue("+%d%% Move Speed" % int(round(inc_ms*100.0)), Color(0.8,0.9,1.0))
		"max_hp":
			var add: int = int(conf.get("per_stack", 2))
			max_health += add
			notify_max_health_changed()
			heal(add)
			_show_stack_cue("+%d Max HP" % add, Color(0.6,0.8,1.0))
		"crit_chance":
			var inc3: float = float(conf.get("per_stack", 0.02))
			crit_chance += inc3
			_show_stack_cue("+%d%% Crit Chance" % int(round(inc3*100.0)), Color(1.0,0.8,0.2))
		"defense":
			var inc4: float = float(conf.get("per_stack", 0.02))
			var before: float = incoming_damage_mult
			var mult: float = max(0.0, 1.0 - inc4)
			var desired: float = before * mult
			if desired < MIN_INCOMING_DAMAGE_MULT:
				incoming_damage_mult = MIN_INCOMING_DAMAGE_MULT
				_handle_defense_overflow(conf, weapon_id, weapon_tier)
			else:
				incoming_damage_mult = desired
				_show_stack_cue("-%d%% Damage Taken" % int(round(inc4 * 100.0)), Color(0.8, 1.0, 0.8))
		"turret_spawn":
			# Spawn a turret immediately near the player (not queued for next wave).
			var pos := global_position + Vector2(randf_range(-80,80), randf_range(-80,80))
			var spawned := false
			var main := get_tree().current_scene
			if main and main.has_method("_spawn_turret_at_with_tier"):
				main._spawn_turret_at_with_tier(pos, 1)
				spawned = true
			elif main and main.has_method("_spawn_turret_at"):
				main._spawn_turret_at(pos)
				spawned = true
			if not spawned:
				var tp = get_tree().get_first_node_in_group("turret_pool")
				if tp and tp.has_method("spawn_turret"):
					tp.call("spawn_turret", pos, 1)
					spawned = true
			_show_stack_cue("+Turret", Color(0.7,1.0,0.3))
		_:
			pass

func _handle_defense_overflow(conf: Dictionary, weapon_id: String, weapon_tier: int) -> void:
	var overflow_gain: float = max(0.0, float(conf.get("per_stack", 0.02)))
	overflow_healing_mult_from_defense *= (1.0 + overflow_gain)
	if weapon_id == "guardian":
		_spawn_guardian_healing_turret(max(1, weapon_tier))
	else:
		_show_stack_cue("+%d%% Healing Power" % int(round(overflow_gain * 100.0)), Color(0.6, 1.0, 0.9))

func _spawn_guardian_healing_turret(tier: int) -> void:
	var pos := global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80))
	var spawned := false
	var main := get_tree().current_scene
	if main and main.has_method("_spawn_turret_at_with_tier"):
		main.call("_spawn_turret_at_with_tier", pos, max(1, tier), "healing")
		spawned = true
	elif main and main.has_method("_spawn_turret_at"):
		# Fallback: spawn default turret and immediately convert via pool if possible
		main.call("_spawn_turret_at", pos, "healing")
		spawned = true
	else:
		var tp = get_tree().get_first_node_in_group("turret_pool")
		if tp and tp.has_method("spawn_turret"):
			tp.call("spawn_turret", pos, max(1, tier), "healing")
			spawned = true
	if spawned:
		_show_stack_cue("+Healing Turret", Color(0.6, 1.0, 0.9))

func _show_stack_cue(msg: String, col: Color) -> void:
	# Simple ring cue above the player
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = col
	var r: float = 14.0
	var segs: int = 20
	var pts := PackedVector2Array()
	for s in range(segs + 1):
		var a := TAU * float(s) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	ring.points = pts
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector2(0, -20)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(1.4, 1.4), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)

	# Floating text cue with the message
	if msg != "":
		var label := Label.new()
		label.text = msg
		label.add_theme_color_override("font_color", col)
		label.modulate = Color(1,1,1,0.0)
		get_tree().current_scene.add_child(label)
		label.global_position = global_position + Vector2(0, -34)
		var tw2 := label.create_tween()
		tw2.tween_property(label, "modulate:a", 1.0, 0.12)
		tw2.parallel().tween_property(label, "position:y", label.position.y - 16.0, 0.35)
		tw2.tween_property(label, "modulate:a", 0.0, 0.18)
		tw2.tween_callback(label.queue_free)

func _ensure_bullet_pool() -> void:
	if bullet_pool == null or not is_instance_valid(bullet_pool):
		var p = get_tree().get_first_node_in_group("bullet_pool")
		if p != null:
			bullet_pool = p

# Detailed instrumentation for the anti-teleport guard to diagnose root cause.
func _log_guard_event(step_dist: float, expected_step: float, hard_cap: float, delta: float, attempted_pos: Vector2, prev_pos: Vector2) -> void:
	var paused := get_tree().paused
	var cs := get_tree().current_scene
	var intermission := false
	var awaiting_character := false
	var ui_modal := false
	var physics_frame: int = Engine.get_physics_frames()
	var stack_lines: Array = []
	if not Engine.is_editor_hint():
		stack_lines = get_stack()
	if cs != null:
		# Safely probe scene state flags if present
		var v1 = null
		var v2 = null
		if cs.has_method("get"):
			v1 = cs.get("in_intermission")
			v2 = cs.get("awaiting_character")
		if v1 != null:
			intermission = bool(v1)
		if v2 != null:
			awaiting_character = bool(v2)
		if cs.has_method("_ui_modal_active"):
			ui_modal = bool(cs.call("_ui_modal_active"))

	# Enemy counts (total and active+visible)
	var enemies_all: Array = get_tree().get_nodes_in_group("enemies")
	var enemies_total: int = enemies_all.size()
	var enemies_active_visible: int = 0
	for e in enemies_all:
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
		if ok:
			enemies_active_visible += 1

	# Beam channel state snapshot
	var beams: Array = get_tree().get_nodes_in_group("beams")
	var beams_total: int = beams.size()
	var beams_channeling: int = 0
	var beams_visible: int = 0
	var beam_details: Array = []
	for b in beams:
		if not is_instance_valid(b):
			continue
		if b.has_method("is_channeling") and bool(b.call("is_channeling")):
			beams_channeling += 1
		if b.visible:
			beams_visible += 1
		if beam_details.size() < 3 and b.has_method("debug_state"):
			beam_details.append(b.call("debug_state"))

	var max_allowed = max(expected_step, hard_cap)
	print("[Guard] Cancelled abnormal move: ", step_dist, " px (limit ", max_allowed, ")")
	print("  delta=", delta, " move_speed=", move_speed, " vel=", velocity, " | vel_len=", velocity.length())
	print("  prev_pos=", prev_pos, " attempted_pos=", attempted_pos)
	print("  paused=", paused, " intermission=", intermission, " awaiting_character=", awaiting_character, " ui_modal=", ui_modal)
	print("  enemies total=", enemies_total, " active_visible=", enemies_active_visible)
	print("  beams total=", beams_total, " channeling=", beams_channeling, " visible=", beams_visible)
	if beam_details.size() > 0:
		print("  beam_details=", beam_details)
	print("  physics_frame=", physics_frame)
	if stack_lines.size() > 0:
		print("  stack:")
		for s in stack_lines:
			print("    ", str(s))
