extends Control

@onready var text: RichTextLabel = $RichText

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if has_signal("visibility_changed"):
		visibility_changed.connect(_on_visibility_changed)
	refresh()

func _on_visibility_changed() -> void:
	if visible:
		refresh()

func refresh() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var bullet_pool = get_tree().get_first_node_in_group("bullet_pool")

	# Core multipliers and caps
	var dmg_mult: float = float(player.get("damage_mult"))
	var atk_mult: float = float(player.get("attack_speed_mult"))
	var atk_cap: float = float(player.MAX_ATTACK_SPEED_MULT)
	var proj_bonus: int = int(player.get("projectiles_per_shot"))
	var proj_cap: int = int(player.MAX_PROJECTILE_BONUS)
	var proj_speed_mult: float = float(player.get("projectile_speed_mult"))
	var per_shot_cap: int = int(player.MAX_TOTAL_PROJECTILES)
	var min_interval: float = float(player.MIN_WEAPON_INTERVAL)
	var soft_proj_cap: int = 200

	# Additional player attributes
	var hp: int = int(player.get("health"))
	var hp_max: int = int(player.get("max_health"))
	var regen: float = float(player.get("regen_per_second"))
	var move_spd: float = float(player.get("move_speed"))
	var spread_deg: float = float(player.get("spread_degrees"))
	var currency_mult: float = float(player.get("currency_gain_mult"))
	var lifesteal: int = int(player.get("lifesteal_per_kill"))

	# Elemental / Explosive scaling stats
	var elemental_power: float = 1.0
	var _epv = player.get("elemental_damage_mult")
	if _epv != null:
		elemental_power = float(_epv)
	var explosive_power: float = 1.0
	var _xp = player.get("explosive_power_mult")
	if _xp != null:
		explosive_power = float(_xp)

	var beam_threshold: float = 900.0
	if bullet_pool and bullet_pool.has_method("get_beam_threshold"):
		beam_threshold = float(bullet_pool.call("get_beam_threshold"))

	var as_overflow_mult: float = float(player.get("overflow_damage_mult_from_attack_speed")) if player.has_method("get") else 1.0
	var proj_overflow_mult: float = float(player.get("overflow_damage_mult_from_projectiles")) if player.has_method("get") else 1.0

	var lines: Array[String] = []
	lines.append("[b]Player Stats[/b]")
	lines.append("Health: %d/%d  |  Regen: %.1f/s" % [hp, hp_max, regen])
	lines.append("Move Speed: %.0f px/s" % move_spd)
	lines.append("Damage: x%.2f" % dmg_mult)
	var as_line := "Attack Speed: x%.2f (cap x%.2f)" % [atk_mult, atk_cap]
	if as_overflow_mult > 1.0:
		var pct := int(round((as_overflow_mult - 1.0) * 100.0))
		as_line += "  |  Overflow to Damage: +%d%%" % pct
	lines.append(as_line)
	var proj_line := "Projectiles: +%d (cap +%d)" % [proj_bonus, proj_cap]
	if proj_overflow_mult > 1.0:
		var pct2 := int(round((proj_overflow_mult - 1.0) * 100.0))
		proj_line += "  |  Overflow to Damage: +%d%%" % pct2
	lines.append(proj_line)
	lines.append("Projectile Speed: x%.2f  |  Beam threshold: %.0f px/s" % [proj_speed_mult, beam_threshold])
	lines.append("Per-shot projectile cap: %d  |  Overflow scales damage x(shots/cap)" % per_shot_cap)
	lines.append("Soft projectile count cap: %d  |  Overload reduces shots, boosts damage" % soft_proj_cap)
	lines.append("Min weapon interval: %.2fs" % min_interval)
	lines.append("Currency Gain: x%.2f" % currency_mult)
	lines.append("Lifesteal: +%d HP per kill" % lifesteal)
	lines.append("Elemental Power: x%.2f" % elemental_power)
	lines.append("Explosive Power: x%.2f" % explosive_power)
	lines.append("Spread: %.1f°" % spread_deg)

	text.bbcode_enabled = true
	text.text = "\n".join(lines)

