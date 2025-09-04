extends Control

@onready var text: RichTextLabel = $RichText

const ShopLib = preload("res://scripts/shop.gd")

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
	for it in ShopLib.items():
		id_to_name[String(it["id"])] = String(it["name"])

	var c := int(counts.get("money_charm", 0))
	if c > 0:
		var mult := pow(1.2, float(c))
		var pct := int(round((mult - 1.0) * 100.0))
		lines.append("%s x%d — +%d%% currency (x%.2f)" % [id_to_name.get("money_charm","Money Charm"), c, pct, mult])

	c = int(counts.get("scope", 0))
	if c > 0:
		lines.append("%s x%d — +%d projectiles" % [id_to_name.get("scope","Scope"), c, c])

	c = int(counts.get("overcharger", 0))
	if c > 0:
		var mult2 := pow(1.15, float(c))
		var pct2 := int(round((mult2 - 1.0) * 100.0))
		lines.append("%s x%d — +%d%% attack speed (x%.2f)" % [id_to_name.get("overcharger","Overcharger"), c, pct2, mult2])

	c = int(counts.get("adrenaline", 0))
	if c > 0:
		var regen := 0.5 * float(c)
		lines.append("%s x%d — +%.1f HP/s regen" % [id_to_name.get("adrenaline","Adrenaline"), c, regen])

	c = int(counts.get("lifesteal_charm", 0))
	if c > 0:
		lines.append("%s x%d — +%d HP per kill" % [id_to_name.get("lifesteal_charm","Lifesteal Charm"), c, c])

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

