extends Control

@onready var text: RichTextLabel = $RichText

const ShopLib = preload("res://scripts/shop.gd")

func _rarity_color_hex(r: String) -> String:
	match r:
		"Common": return "#D9D9D9"
		"Uncommon": return "#66FF66"
		"Rare": return "#6699FF"
		"Epic": return "#CC66FF"
		"Legendary": return "#FFB233"
		_: return "#FFFFFF"

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

func name_of(id: String, fallback: String, id_to_name: Dictionary) -> String:
	return String(id_to_name.get(id, fallback))

func _refresh() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var counts: Dictionary = {}
	var cdict = player.get("item_counts") if player.has_method("get") else null
	if cdict != null:
		counts = cdict
	var lines: Array[String] = []
	var id_to_name: Dictionary = {}
	var id_to_rarity: Dictionary = {}
	for it in ShopLib.items():
		var iid := String(it["id"])
		id_to_name[iid] = String(it["name"])
		id_to_rarity[iid] = String(it.get("rarity", "Common"))

	# Economy
	var n := int(counts.get("money_charm", 0))
	if n > 0:
		var mul := pow(1.2, float(n))
		lines.append(_fmt_line("money_charm", "%s x%d — +%d%% currency (x%.2f)" % [name_of("money_charm","Money Charm", id_to_name), n, int(round((mul-1.0)*100.0)), mul], id_to_rarity))

	# Core combat items
	n = int(counts.get("scope", 0))
	if n > 0:
		lines.append(_fmt_line("scope", "%s x%d — +%d projectiles" % [name_of("scope","Scope", id_to_name), n, n], id_to_rarity))
	n = int(counts.get("overcharger", 0))
	if n > 0:
		var mul_o := pow(1.15, float(n))
		lines.append(_fmt_line("overcharger", "%s x%d — +%d%% attack speed (x%.2f)" % [name_of("overcharger","Overcharger", id_to_name), n, int(round((mul_o-1.0)*100.0)), mul_o], id_to_rarity))
	n = int(counts.get("adrenaline", 0))
	if n > 0:
		lines.append(_fmt_line("adrenaline", "%s x%d — +%.1f HP/s regen" % [name_of("adrenaline","Adrenaline", id_to_name), n, 0.5*float(n)], id_to_rarity))
	n = int(counts.get("lifesteal_charm", 0))
	if n > 0:
		lines.append(_fmt_line("lifesteal_charm", "%s x%d — +%d HP per kill" % [name_of("lifesteal_charm","Lifesteal Charm", id_to_name), n, n], id_to_rarity))

	# Movement/projectile
	n = int(counts.get("boots", 0))
	if n > 0:
		var mul_b := pow(1.10, float(n))
		lines.append(_fmt_line("boots", "%s x%d — +%d%% move speed (x%.2f)" % [name_of("boots","Boots", id_to_name), n, int(round((mul_b-1.0)*100.0)), mul_b], id_to_rarity))
	n = int(counts.get("caffeine", 0))
	if n > 0:
		var mul_c := pow(1.10, float(n))
		lines.append(_fmt_line("caffeine", "%s x%d — +%d%% attack speed (x%.2f)" % [name_of("caffeine","Caffeine", id_to_name), n, int(round((mul_c-1.0)*100.0)), mul_c], id_to_rarity))
	n = int(counts.get("ammo_belt", 0))
	if n > 0:
		lines.append(_fmt_line("ammo_belt", "%s x%d — +%d projectiles" % [name_of("ammo_belt","Ammo Belt", id_to_name), n, n], id_to_rarity))
	n = int(counts.get("aerodynamics", 0))
	if n > 0:
		var mul_a := pow(1.20, float(n))
		lines.append(_fmt_line("aerodynamics", "%s x%d — +%d%% projectile speed (x%.2f)" % [name_of("aerodynamics","Aerodynamics", id_to_name), n, int(round((mul_a-1.0)*100.0)), mul_a], id_to_rarity))

	# Survivability
	n = int(counts.get("protein_bar", 0))
	if n > 0:
		lines.append(_fmt_line("protein_bar", "%s x%d — +%d Max HP" % [name_of("protein_bar","Protein Bar", id_to_name), n, 15*n], id_to_rarity))
	n = int(counts.get("medkit", 0))
	if n > 0:
		lines.append(_fmt_line("medkit", "%s x%d — +%.1f HP/s regen" % [name_of("medkit","Medkit", id_to_name), n, 1.0*float(n)], id_to_rarity))

	# Economy and damage
	n = int(counts.get("greed_token", 0))
	if n > 0:
		var mul_g := pow(1.15, float(n))
		lines.append(_fmt_line("greed_token", "%s x%d — +%d%% currency (x%.2f)" % [name_of("greed_token","Greed Token", id_to_name), n, int(round((mul_g-1.0)*100.0)), mul_g], id_to_rarity))
	n = int(counts.get("vampiric_orb", 0))
	if n > 0:
		lines.append(_fmt_line("vampiric_orb", "%s x%d — +%d HP per kill" % [name_of("vampiric_orb","Vampiric Orb", id_to_name), n, n], id_to_rarity))
	n = int(counts.get("power_core", 0))
	if n > 0:
		var mul_p := pow(1.10, float(n))
		lines.append(_fmt_line("power_core", "%s x%d — +%d%% damage (x%.2f)" % [name_of("power_core","Power Core", id_to_name), n, int(round((mul_p-1.0)*100.0)), mul_p], id_to_rarity))

	# Spread control
	n = int(counts.get("stabilizer", 0))
	if n > 0:
		lines.append(_fmt_line("stabilizer", "%s x%d — -%d° spread" % [name_of("stabilizer","Stabilizer", id_to_name), n, 2*n], id_to_rarity))

	# Elemental Power items
	for id in ["elemental_amp","elemental_catalyst","elemental_core","arcanum"]:
		n = int(counts.get(id, 0))
		if n <= 0:
			continue
		var f := 1.0
		match id:
			"elemental_amp": f = 1.10
			"elemental_catalyst": f = 1.20
			"elemental_core": f = 1.30
			"arcanum": f = 1.40
		var mul_e := pow(f, float(n))
		lines.append(_fmt_line(id, "%s x%d — +%d%% Elemental Power (x%.2f)" % [name_of(id, id.capitalize(), id_to_name), n, int(round((mul_e-1.0)*100.0)), mul_e], id_to_rarity))

	# Explosive Power items
	for id in ["blast_caps","demolition_kit","payload_upgrade","warhead"]:
		n = int(counts.get(id, 0))
		if n <= 0:
			continue
		var fx := 1.0
		match id:
			"blast_caps": fx = 1.10
			"demolition_kit": fx = 1.15
			"payload_upgrade": fx = 1.20
			"warhead": fx = 1.30
		var mul_x := pow(fx, float(n))
		lines.append(_fmt_line(id, "%s x%d — +%d%% Explosive Power (x%.2f)" % [name_of(id, id.capitalize(), id_to_name), n, int(round((mul_x-1.0)*100.0)), mul_x], id_to_rarity))

	# Cross-synergy items
	n = int(counts.get("volatile_rounds", 0))
	if n > 0:
		var ch1: float = min(0.5, 0.08 * float(n))
		lines.append(_fmt_line("volatile_rounds", "%s x%d — %d%% chance for non-explosive hits to explode" % [name_of("volatile_rounds","Volatile Rounds", id_to_name), n, int(round(ch1*100.0))], id_to_rarity))
	n = int(counts.get("elemental_fuse", 0))
	if n > 0:
		var ch2: float = min(0.6, 0.10 * float(n))
		lines.append(_fmt_line("elemental_fuse", "%s x%d — %d%% chance for non-elemental hits to inflict a random element" % [name_of("elemental_fuse","Elemental Fuse", id_to_name), n, int(round(ch2*100.0))], id_to_rarity))
	n = int(counts.get("payload_catalyst", 0))
	if n > 0:
		var ch3: float = min(0.5, 0.10 * float(n))
		lines.append(_fmt_line("payload_catalyst", "%s x%d — %d%% chance for explosions to apply a random element in the blast" % [name_of("payload_catalyst","Payload Catalyst", id_to_name), n, int(round(ch3*100.0))], id_to_rarity))
	n = int(counts.get("superconductor", 0))
	if n > 0:
		lines.append(_fmt_line("superconductor", "%s x%d — Shock arcs +%d, radius +%d" % [name_of("superconductor","Superconductor", id_to_name), n, n, 12*n], id_to_rarity))

	# Turret queued display
	n = int(counts.get("turret", 0))
	if main and main.has_method("get") and bool(main.get("in_intermission")):
		var pending := int(main.get("pending_turrets")) if main.has_method("get") else 0
		if n > 0 or pending > 0:
			var left := name_of("turret","Turret", id_to_name)
			if n > 0:
				left += " x%d" % n
			lines.append("%s — Queued: %d next wave" % [left, pending])

	if lines.size() == 0:
		text.text = "No items yet. Buy items in the shop to stack effects."
	else:
		text.text = "[b]Items & Effects[/b]\n" + "\n".join(lines)
