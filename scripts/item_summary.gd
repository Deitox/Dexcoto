extends Control

@onready var text: RichTextLabel = $RichText

const ShopLib = preload("res://scripts/shop.gd")

func _rarity_color_hex(r: String) -> String:
	match r:
		"Common":
			return "#D9D9D9"
		"Uncommon":
			return "#66FF66"
		"Rare":
			return "#6699FF"
		"Epic":
			return "#CC66FF"
		"Legendary":
			return "#FFB233"
		_:
			return "#FFFFFF"

func _fmt_line(item_id: String, raw: String, id_to_rarity: Dictionary) -> String:
	var rar := String(id_to_rarity.get(item_id, "Common"))
	var col := _rarity_color_hex(rar)
	return "[color=%s]%s[/color]" % [col, raw]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if has_signal("visibility_changed"):
		visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()

func refresh() -> void:
	_refresh()

func _refresh() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var counts: Dictionary = {}
	if player and player.has_method("get"):
		var cdict = player.get("item_counts")
		if cdict != null:
			counts = cdict
	var lines: Array[String] = []
	var id_to_name: Dictionary = {}
	var id_to_rarity: Dictionary = {}
	for it in ShopLib.items():
		var iid := String(it["id"])
		id_to_name[iid] = String(it["name"])
		id_to_rarity[iid] = String(it.get("rarity", "Common"))

	var c := int(counts.get("money_charm", 0))
	if c > 0:
		var mult := pow(1.2, float(c))
		var pct := int(round((mult - 1.0) * 100.0))
		lines.append(_fmt_line("money_charm", "%s x%d — +%d%% currency (x%.2f)" % [id_to_name.get("money_charm","Money Charm"), c, pct, mult], id_to_rarity))

	c = int(counts.get("scope", 0))
	if c > 0:
		lines.append(_fmt_line("scope", "%s x%d — +%d projectiles" % [id_to_name.get("scope","Scope"), c, c], id_to_rarity))

	c = int(counts.get("overcharger", 0))
	if c > 0:
		var mult2 := pow(1.15, float(c))
		var pct2 := int(round((mult2 - 1.0) * 100.0))
		lines.append(_fmt_line("overcharger", "%s x%d — +%d%% attack speed (x%.2f)" % [id_to_name.get("overcharger","Overcharger"), c, pct2, mult2], id_to_rarity))

	c = int(counts.get("adrenaline", 0))
	if c > 0:
		var regen := 0.5 * float(c)
		lines.append(_fmt_line("adrenaline", "%s x%d — +%.1f HP/s regen" % [id_to_name.get("adrenaline","Adrenaline"), c, regen], id_to_rarity))

	c = int(counts.get("lifesteal_charm", 0))
	if c > 0:
		lines.append(_fmt_line("lifesteal_charm", "%s x%d — +%d HP per kill" % [id_to_name.get("lifesteal_charm","Lifesteal Charm"), c, c], id_to_rarity))

	# New items
	c = int(counts.get("boots", 0))
	if c > 0:
		var mult_b := pow(1.10, float(c))
		var pct_b := int(round((mult_b - 1.0) * 100.0))
		lines.append(_fmt_line("boots", "%s x%d — +%d%% move speed (x%.2f)" % [id_to_name.get("boots","Boots"), c, pct_b, mult_b], id_to_rarity))

	c = int(counts.get("caffeine", 0))
	if c > 0:
		var mult_c := pow(1.10, float(c))
		var pct_c := int(round((mult_c - 1.0) * 100.0))
		lines.append(_fmt_line("caffeine", "%s x%d — +%d%% attack speed (x%.2f)" % [id_to_name.get("caffeine","Caffeine"), c, pct_c, mult_c], id_to_rarity))

	c = int(counts.get("ammo_belt", 0))
	if c > 0:
		lines.append(_fmt_line("ammo_belt", "%s x%d — +%d projectiles" % [id_to_name.get("ammo_belt","Ammo Belt"), c, c], id_to_rarity))

	c = int(counts.get("aerodynamics", 0))
	if c > 0:
		var mult_aero := pow(1.20, float(c))
		var pct_aero := int(round((mult_aero - 1.0) * 100.0))
		lines.append(_fmt_line("aerodynamics", "%s x%d — +%d%% projectile speed (x%.2f)" % [id_to_name.get("aerodynamics","Aerodynamics"), c, pct_aero, mult_aero], id_to_rarity))

	c = int(counts.get("protein_bar", 0))
	if c > 0:
		var hp := 15 * c
		lines.append(_fmt_line("protein_bar", "%s x%d — +%d Max HP" % [id_to_name.get("protein_bar","Protein Bar"), c, hp], id_to_rarity))

	c = int(counts.get("medkit", 0))
	if c > 0:
		var regen2 := 1.0 * float(c)
		lines.append(_fmt_line("medkit", "%s x%d — +%.1f HP/s regen" % [id_to_name.get("medkit","Medkit"), c, regen2], id_to_rarity))

	c = int(counts.get("greed_token", 0))
	if c > 0:
		var mult_g := pow(1.15, float(c))
		var pct_g := int(round((mult_g - 1.0) * 100.0))
		lines.append(_fmt_line("greed_token", "%s x%d — +%d%% currency (x%.2f)" % [id_to_name.get("greed_token","Greed Token"), c, pct_g, mult_g], id_to_rarity))

	c = int(counts.get("vampiric_orb", 0))
	if c > 0:
		lines.append(_fmt_line("vampiric_orb", "%s x%d — +%d HP per kill" % [id_to_name.get("vampiric_orb","Vampiric Orb"), c, c], id_to_rarity))

	c = int(counts.get("power_core", 0))
	if c > 0:
		var mult_p := pow(1.10, float(c))
		var pct_p := int(round((mult_p - 1.0) * 100.0))
		lines.append(_fmt_line("power_core", "%s x%d — +%d%% damage (x%.2f)" % [id_to_name.get("power_core","Power Core"), c, pct_p, mult_p], id_to_rarity))

	c = int(counts.get("stabilizer", 0))
	if c > 0:
		var total := 2 * c
		lines.append(_fmt_line("stabilizer", "%s x%d — -%d° spread" % [id_to_name.get("stabilizer","Stabilizer"), c, total], id_to_rarity))

	# Turret: pending effect is per-wave, show queued amount if in intermission
	c = int(counts.get("turret", 0))
	if main and main.has_method("get") and main.get("in_intermission"):
		var pending := int(main.get("pending_turrets")) if main.has_method("get") else 0
		if c > 0 or pending > 0:
			var eff := "Queued: %d next wave" % pending
			var base_name := String(id_to_name.get("turret","Turret"))
			var left := base_name
			if c > 0:
				left += " x%d" % c
			lines.append("%s — %s" % [left, eff])

	if lines.size() == 0:
		text.text = "No items yet. Buy items in the shop to stack effects."
	else:
		text.text = "[b]Items & Effects[/b]\n" + "\n".join(lines)
