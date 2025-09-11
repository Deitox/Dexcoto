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

func _ready() -> void:
	health = max_health
	bullet_pool = get_tree().get_first_node_in_group("bullet_pool")
	# Ensure we pick up the pool if its _ready adds the group after ours runs
	call_deferred("_ensure_bullet_pool")
	_last_pos = global_position

func set_position_and_reset_guard(pos: Vector2) -> void:
	# Public helper to intentionally reposition the player without triggering the anti-teleport guard.
	global_position = pos
	_last_pos = pos
	velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	# Regen
	if regen_per_second > 0.0 and health > 0 and health < max_health:
		_regen_accum += regen_per_second * delta
		var heal: int = int(_regen_accum)
		if heal > 0:
			_regen_accum -= float(heal)
			health = clamp(health + heal, 0, max_health)

	var input_dir: Vector2 = Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_dir * move_speed
	move_and_slide()

	# Anti-teleport guard: if we moved an unexpectedly large distance in one physics frame,
	# cancel the move and zero velocity. This is defensive while we hunt the root cause.
	var step_dist: float = global_position.distance_to(_last_pos)
	var expected_step: float = move_speed * delta * 2.5 # generous factor for diagonals/buffs
	var hard_cap: float = 320.0 # absolute threshold in px/frame
	if step_dist > max(expected_step, hard_cap):
		global_position = _last_pos
		velocity = Vector2.ZERO
		if _teleport_log_cooldown <= 0.0:
			print("[Guard] Cancelled abnormal move: ", step_dist)
			_teleport_log_cooldown = 1.0
	_teleport_log_cooldown = max(0.0, _teleport_log_cooldown - delta)
	_last_pos = global_position

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
	health -= amount
	if health <= 0:
		health = 0
		emit_signal("died")

# Compute final damage after rolling crits.
# - Crit chance is capped at 100% for the roll; overflow above 1.0 increases crit damage multiplier additively.
# - Returns an int scaled from base_damage.
func compute_crit_damage(base_damage: int) -> int:
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
	return int(round(dmg))

func apply_upgrade(upg: Dictionary) -> void:
	var t: String = String(upg.get("type", ""))
	var v: Variant = upg.get("value")
	match t:
		"attack_speed":
			attack_speed_mult *= (1.0 + float(v))
			if attack_speed_mult > MAX_ATTACK_SPEED_MULT:
				var overflow_factor: float = attack_speed_mult / MAX_ATTACK_SPEED_MULT
				attack_speed_mult = MAX_ATTACK_SPEED_MULT
				damage_mult *= overflow_factor
				overflow_damage_mult_from_attack_speed *= overflow_factor
		"damage":
			damage_mult *= (1.0 + float(v))
		"move_speed":
			move_speed = move_speed * (1.0 + float(v))
		"max_hp":
			max_health += int(v)
			health = min(max_health, health + int(v))
		"bullet_speed":
			projectile_speed_mult *= (1.0 + float(v))
		"regen":
			regen_per_second += float(v)
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
	if kind != "weapon":
		return
	var wid: String = String(source.get("weapon_id",""))
	if wid == "":
		return
	# Find the matching weapon instance to read its stack config and tier
	var picked: Dictionary = {}
	for w in weapons:
		if String(w.get("id","")) == wid:
			picked = w
			break
	if picked.is_empty() or not picked.has("stack"):
		return
	var sconf: Dictionary = picked["stack"]
	var base_kills: int = int(sconf.get("base_kills", 5))
	var tier: int = int(picked.get("tier", 1))
	# Higher tier requires fewer kills: divide by (1 + 0.25*(tier-1))
	var denom: float = 1.0 + 0.25 * float(max(0, tier - 1))
	var need: int = max(1, int(round(float(base_kills) / denom)))
	var cur: int = int(_kill_counters.get(wid, 0)) + 1
	if cur >= need:
		_kill_counters[wid] = 0
		_apply_stack_effect(String(sconf.get("type","")), sconf)
	else:
		_kill_counters[wid] = cur

func _apply_stack_effect(stype: String, conf: Dictionary) -> void:
	match stype:
		"damage":
			var inc: float = float(conf.get("per_stack", 0.02))
			damage_mult *= (1.0 + inc)
			_show_stack_cue("+%d%% Damage" % int(round(inc*100.0)), Color(1.0,0.5,0.5))
		"attack_speed":
			var inc2: float = float(conf.get("per_stack", 0.02))
			attack_speed_mult *= (1.0 + inc2)
			_show_stack_cue("+%d%% Attack Speed" % int(round(inc2*100.0)), Color(0.6,1.0,0.6))
		"max_hp":
			var add: int = int(conf.get("per_stack", 2))
			max_health += add
			health = min(max_health, health + add)
			_show_stack_cue("+%d Max HP" % add, Color(0.6,0.8,1.0))
		"crit_chance":
			var inc3: float = float(conf.get("per_stack", 0.02))
			crit_chance += inc3
			_show_stack_cue("+%d%% Crit Chance" % int(round(inc3*100.0)), Color(1.0,0.8,0.2))
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
