extends Node2D

func _refresh_item_summaries() -> void:
	var paths := [
		"UI/ShopPanel/VBox/Summary",
		"UI/UpgradePanel/VBox/Summary",
		"UI/PausePanel/VBox/Summary",
		"UI/StatsPanel/VBox/Stats",
	]
	for p in paths:
		if has_node(p):
			var n = get_node(p)
			if n and n.has_method("refresh"):
				n.call("refresh")

func _update_stats_panel_visibility() -> void:
	var sp := $UI/StatsPanel if has_node("UI/StatsPanel") else null
	if sp == null:
		return
	var show_stats := false
	if in_intermission:
		show_stats = true
	elif pause_panel and pause_panel.visible:
		show_stats = true
	else:
		show_stats = false
	sp.visible = show_stats
	if show_stats:
		_refresh_stats_panel_now()

func _refresh_stats_panel_now() -> void:
	var stats_node := $UI/StatsPanel/VBox/Stats if has_node("UI/StatsPanel/VBox/Stats") else null
	if stats_node and stats_node.has_method("refresh"):
		stats_node.call("refresh")

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")

@onready var player: Node2D = $Player
@onready var wave_timer: Timer = $WaveTimer
@onready var spawn_timer: Timer = $SpawnTimer
@onready var ui_health: Label = $UI/MarginContainer/HBoxContainer/Health
@onready var ui_level: Label = $UI/MarginContainer/HBoxContainer/Level
@onready var ui_wave: Label = $UI/MarginContainer/HBoxContainer/Wave
@onready var ui_time: Label = $UI/MarginContainer/HBoxContainer/Time
@onready var ui_score: Label = $UI/MarginContainer/HBoxContainer/Score
@onready var upgrade_panel: Control = $UI/UpgradePanel
@onready var upgrade_title: Label = $UI/UpgradePanel/VBox/Title
@onready var btn1: Button = $UI/UpgradePanel/VBox/Options/Option1
@onready var btn2: Button = $UI/UpgradePanel/VBox/Options/Option2
@onready var btn3: Button = $UI/UpgradePanel/VBox/Options/Option3
@onready var arena_bounds: Node = $ArenaBounds

# Shop UI
@onready var shop_panel: Control = $UI/ShopPanel
@onready var shop_title: Label = $UI/ShopPanel/VBox/Title
@onready var shop_opt1: Button = $UI/ShopPanel/VBox/Options/Option1
@onready var shop_opt2: Button = $UI/ShopPanel/VBox/Options/Option2
@onready var shop_opt3: Button = $UI/ShopPanel/VBox/Options/Option3
@onready var shop_reroll: Button = $UI/ShopPanel/VBox/Bottom/Reroll
@onready var shop_start: Button = $UI/ShopPanel/VBox/Bottom/StartNext

# Pause menu UI
@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_resume: Button = $UI/PausePanel/VBox/Resume
@onready var pause_restart: Button = $UI/PausePanel/VBox/Restart
@onready var pause_quit: Button = $UI/PausePanel/VBox/Quit

# Character select UI
@onready var character_panel: Control = $UI/CharacterSelect
@onready var char_title: Label = $UI/CharacterSelect/VBox/Title
@onready var char_opts: GridContainer = $UI/CharacterSelect/VBox/Options
@onready var char_diff: OptionButton = $UI/CharacterSelect/VBox/DifficultyRow/Difficulty

# Use global class UpgradeDB (from upgrades.gd)
const ShopLib = preload("res://scripts/shop.gd")
const TURRET_SCENE: PackedScene = preload("res://scenes/Turret.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/Boss.tscn")

# HUD highlight map for weapon changes while in shop
var _hud_highlight: Dictionary = {}

# Performance caps (raised for higher density)
const SOFT_CAP_ENEMIES: int = 20
const MAX_ENEMIES: int = 40

# Spawn grouping and telegraphing
const GROUP_BASE_DELAY: float = 0.6
const GROUP_STAGGER: float = 0.12
const GROUP_GAP_MIN: float = 1.6
const GROUP_GAP_MAX: float = 3.2

# Undersaturation boosting: increase spawns when few enemies are active
const LOW_ENEMY_FRACTION: float = 0.33 # below this % of soft cap, boost
const LOW_ENEMY_BOOST: float = 1.5     # multiply group size / count
const VERY_LOW_ENEMIES: int = 4        # if at or below, use stronger boost
const VERY_LOW_BOOST: float = 2.25
const LOW_ENEMY_MIN_GAP: float = 0.25  # tighten gap when low

var wave: int = 1
var score: int = 0
var wave_time: float = 20.0
var elapsed: float = 0.0
var is_game_over: bool = false
var in_intermission: bool = false
var awaiting_character: bool = true

var level: int = 1
var xp: int = 0
var levels_gained_this_wave: int = 0
var pending_choices: int = 0
var current_choices: Array[Dictionary] = []

# Currency and shop
var currency_total: int = 0
var currency_gained_this_wave: int = 0
var shop_offers: Array[Dictionary] = []

var pending_turrets: int = 0
var enemy_pool: Node = null
var turret_pool: Node = null

# Difficulty
@export_enum("Easy", "Normal", "Hard", "Insane") var difficulty: String = "Normal"

func _difficulty_params() -> Dictionary:
	# Returns multipliers and knobs per difficulty
	# count_mult: scales number of enemies per spawn tick
	# cadence_mult: scales spawn timer interval (higher = slower spawns)
	# tier_bonus: flat tier offset (applied on top of wave-based tier)
	# cap_mult: scales soft/hard caps used when adjusting pressure
	# group_max: max size of a spawn group
	var d := String(difficulty)
	match d:
		"Easy":
			return {"count_mult": 0.75, "cadence_mult": 1.15, "tier_bonus": -1, "cap_mult": 0.85, "group_max": 5}
		"Hard":
			return {"count_mult": 1.25, "cadence_mult": 0.90, "tier_bonus": 1, "cap_mult": 1.15, "group_max": 6}
		"Insane":
			return {"count_mult": 1.50, "cadence_mult": 0.80, "tier_bonus": 2, "cap_mult": 1.30, "group_max": 7}
		_:
			return {"count_mult": 1.00, "cadence_mult": 1.00, "tier_bonus": 0, "cap_mult": 1.00, "group_max": 5}

func _ready() -> void:
	randomize()
	player.add_to_group("player")
	player.connect("died", Callable(self, "_on_player_died"))

	# Pools
	if has_node("/root/Main/EnemyPool"):
		enemy_pool = get_node("/root/Main/EnemyPool")
	else:
		enemy_pool = get_tree().get_first_node_in_group("enemy_pool")
	if has_node("/root/Main/TurretPool"):
		turret_pool = get_node("/root/Main/TurretPool")
	else:
		turret_pool = get_tree().get_first_node_in_group("turret_pool")

	# Set initial wave duration based on wave number
	wave_time = _compute_wave_duration(wave)
	wave_timer.wait_time = wave_time
	wave_timer.timeout.connect(_on_wave_timer_timeout)

	spawn_timer.wait_time = 1.0
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	# Pause menu signals
	if pause_resume:
		pause_resume.pressed.connect(_on_pause_resume)
	if pause_restart:
		pause_restart.pressed.connect(_on_pause_restart)
	if pause_quit:
		pause_quit.pressed.connect(_on_pause_quit)

	_show_character_select()
	_update_ui()
	_center_player_in_arena()
	_update_stats_panel_visibility()

	# Connect weapon events to update HUD and notify merges
	if player:
		if not player.is_connected("weapon_added", Callable(self, "_on_weapon_added")):
			player.connect("weapon_added", Callable(self, "_on_weapon_added"))
		if not player.is_connected("weapon_merged", Callable(self, "_on_weapon_merged")):
			player.connect("weapon_merged", Callable(self, "_on_weapon_merged"))

func _center_player_in_arena() -> void:
	if player == null:
		return
	if arena_bounds and arena_bounds.has_method("get_arena_rect"):
		var r: Rect2 = arena_bounds.call("get_arena_rect")
		var cpos := r.position + r.size * 0.5
		if player and player.has_method("set_position_and_reset_guard"):
			player.call("set_position_and_reset_guard", cpos)
		else:
			player.global_position = cpos
		return
	# Fallback to viewport center
	var rect := get_viewport().get_visible_rect()
	var cpos2 := rect.position + rect.size * 0.5
	if player and player.has_method("set_position_and_reset_guard"):
		player.call("set_position_and_reset_guard", cpos2)
	else:
		player.global_position = cpos2

func _process(delta: float) -> void:
	if is_game_over:
		return
	if not in_intermission and not awaiting_character:
		elapsed += delta
		_optimize_runtime()
	_update_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	if pause_panel == null:
		return
	var now_paused := get_tree().paused
	# If already paused due to another UI (shop/upgrade/character), toggle only the pause panel
	# without changing the paused state. Otherwise, toggle pause normally.
	var ui_is_modal := _ui_modal_active()
	if now_paused:
		if ui_is_modal:
			pause_panel.visible = not pause_panel.visible
			_update_stats_panel_visibility()
			return
		# No modal UI: unpause
		get_tree().paused = false
		pause_panel.visible = false
		_update_stats_panel_visibility()
	else:
		pause_panel.visible = true
		get_tree().paused = true
		_update_stats_panel_visibility()

func _on_pause_resume() -> void:
	# If a modal UI (shop/upgrade/character) is active, only hide the pause panel and remain paused.
	if _ui_modal_active():
		pause_panel.visible = false
		_update_stats_panel_visibility()
		return
	get_tree().paused = false
	pause_panel.visible = false
	_update_stats_panel_visibility()

func _on_pause_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_pause_quit() -> void:
	get_tree().quit()

func _on_spawn_timer_timeout() -> void:
	_adjust_spawning()
	_spawn_enemies_grouped()

func _on_wave_timer_timeout() -> void:
	begin_intermission()

func _ui_modal_active() -> bool:
	if shop_panel and shop_panel.visible:
		return true
	if upgrade_panel and upgrade_panel.visible:
		return true
	if character_panel and character_panel.visible:
		return true
	return false


func _active_enemies_count() -> int:
	var total := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var is_active := true
		if e.has_method("get"):
			var a = e.get("active")
			if a != null:
				is_active = bool(a)
		if is_active:
			total += 1
	return total

func _spawn_enemies() -> void:
	# Stronger quantity curve
	var base_count := 3 + int(round(float(wave) * 2.0))

	var enemies := _active_enemies_count()
	var dp: Dictionary = _difficulty_params()
	var cap_scale := _cap_scale_for_wave(wave)
	var soft_cap := int(round(float(SOFT_CAP_ENEMIES) * float(dp.get("cap_mult", 1.0)) * cap_scale))
	var hard_cap := int(round(float(MAX_ENEMIES) * float(dp.get("cap_mult", 1.0)) * cap_scale))
	var count := int(round(float(base_count) * float(dp.get("count_mult", 1.0))))

	# Compute tier with extra ramp from wave 7+
	var tier := _tier_for_wave(wave, dp)

	if enemies > soft_cap:
		# reduce count and increase tier to keep pressure without clutter
		var over := enemies - soft_cap
		count = max(1, int(round(float(base_count) * 0.4)))
		tier += min(3, int(floor(float(over) / 20.0)) + 1)
	else:
		# If we're well below the target density, boost count to catch up fast.
		var low_thresh := int(round(float(soft_cap) * LOW_ENEMY_FRACTION))
		if enemies < low_thresh:
			var boost := VERY_LOW_BOOST if enemies <= VERY_LOW_ENEMIES else LOW_ENEMY_BOOST
			var desired = max(0, low_thresh - enemies)
			count = max(int(ceil(float(count) * boost)), desired)
	# Hard cap: never exceed MAX_ENEMIES active
	var allowed: int = max(0, hard_cap - enemies)
	count = min(count, allowed)
	for i in range(count):
		var pos := _random_spawn_position()
		if enemy_pool and enemy_pool.has_method("spawn_enemy"):
			enemy_pool.call("spawn_enemy", pos, tier, player)
		else:
			var e := enemy_scene.instantiate()
			e.global_position = pos
			e.target = player
			if e.has_method("set_tier"):
				e.set_tier(tier)
			add_child(e)

func _spawn_enemies_grouped() -> void:
	# Compute baseline like _spawn_enemies(), but spawn a smaller group with telegraphs and stagger.
	var base_count := 3 + int(round(float(wave) * 2.0))
	var enemies := _active_enemies_count()
	var dp: Dictionary = _difficulty_params()
	var cap_scale := _cap_scale_for_wave(wave)
	var soft_cap := int(round(float(SOFT_CAP_ENEMIES) * float(dp.get("cap_mult", 1.0)) * cap_scale))
	var hard_cap := int(round(float(MAX_ENEMIES) * float(dp.get("cap_mult", 1.0)) * cap_scale))
	var count := int(round(float(base_count) * float(dp.get("count_mult", 1.0))))

	# Compute tier with extra ramp from wave 7+
	var tier := _tier_for_wave(wave, dp)

	if enemies > soft_cap:
		var over := enemies - soft_cap
		count = max(1, int(round(float(base_count) * 0.4)))
		tier += min(3, int(floor(float(over) / 20.0)) + 1)
	else:
		# Boost spawn size when enemy count is too low.
		var low_thresh := int(round(float(soft_cap) * LOW_ENEMY_FRACTION))
		if enemies < low_thresh:
			var boost := VERY_LOW_BOOST if enemies <= VERY_LOW_ENEMIES else LOW_ENEMY_BOOST
			var desired = max(0, low_thresh - enemies)
			count = max(int(ceil(float(count) * boost)), desired)
	var allowed: int = max(0, hard_cap - enemies)
	count = min(count, allowed)
	if count <= 0:
		# Back off next group
		spawn_timer.wait_time = min(3.5, spawn_timer.wait_time * 1.2)
		return
	# Choose a group size and positions (larger groups as waves rise)
	var gmin := 2
	var gmax := int(dp.get("group_max", 5)) + int(clamp(floor(float(wave) / 3.0), 0, 6))
	var gsize: int
	# When low on enemies, bias toward larger groups to catch up quickly.
	var low_thresh2 := int(round(float(soft_cap) * LOW_ENEMY_FRACTION))
	if enemies < low_thresh2:
		gsize = min(max(gmin, count), gmax)
	else:
		gsize = int(clamp(randi() % (gmax - gmin + 1) + gmin, 1, max(1, count)))
	var positions: Array = []
	for i in range(gsize):
		positions.append(_random_spawn_position())
	# Spawn telegraphed group if pool supports it
	if enemy_pool and enemy_pool.has_method("spawn_enemy_group"):
		enemy_pool.call("spawn_enemy_group", positions, tier, player, GROUP_BASE_DELAY, GROUP_STAGGER)
	else:
		# Fallback: schedule individual spawns with telegraph via timers
		for i in range(gsize):
			var pos: Vector2 = positions[i]
			if enemy_pool and enemy_pool.has_method("spawn_enemy_telegraphed"):
				enemy_pool.call("spawn_enemy_telegraphed", pos, tier, player, GROUP_BASE_DELAY + float(i) * GROUP_STAGGER)
			else:
				# Last resort: immediate spawn
				if enemy_pool and enemy_pool.has_method("spawn_enemy"):
					enemy_pool.call("spawn_enemy", pos, tier, player)
				else:
					var e := enemy_scene.instantiate()
					e.global_position = pos
					e.target = player
					if e.has_method("set_tier"):
						e.set_tier(tier)
					add_child(e)
	# Randomize next group gap, adapt by load
	var gap := randf_range(GROUP_GAP_MIN, GROUP_GAP_MAX)
	if enemies > soft_cap:
		gap = min(GROUP_GAP_MAX + 0.8, gap * 1.25)
	else:
		# Tighten gap more aggressively when very few enemies are active.
		var low_thresh3 := int(round(float(soft_cap) * LOW_ENEMY_FRACTION))
		if enemies < low_thresh3:
			gap = max(LOW_ENEMY_MIN_GAP, gap * 0.6)
		else:
			gap = max(GROUP_GAP_MIN * 0.6, gap * 0.9)
	spawn_timer.wait_time = gap

func _adjust_spawning() -> void:
	var enemies := _active_enemies_count()
	var dp: Dictionary = _difficulty_params()
	var cap_scale := _cap_scale_for_wave(wave)
	var soft_cap := int(round(float(SOFT_CAP_ENEMIES) * float(dp.get("cap_mult", 1.0)) * cap_scale))
	if enemies > soft_cap:
		spawn_timer.wait_time = min(3.0, spawn_timer.wait_time * 1.25)
	else:
		# If we are far below the target density, accelerate more aggressively.
		var low_thresh := int(round(float(soft_cap) * LOW_ENEMY_FRACTION))
		if enemies < low_thresh:
			spawn_timer.wait_time = max(LOW_ENEMY_MIN_GAP, spawn_timer.wait_time * 0.75)
		else:
			spawn_timer.wait_time = max(0.25, spawn_timer.wait_time * 0.95)

# Scale enemy caps with wave to allow much larger late-wave counts.
func _cap_scale_for_wave(w: int) -> float:
	# Grows faster than before (~18%/wave), capped at 5x base caps.
	return min(5.0, 1.0 + 0.18 * float(max(0, w - 1)))

# Compute enemy tier from wave with an extra ramp starting at wave 7.
func _tier_for_wave(w: int, dp: Dictionary) -> int:
	var base := 1 + int(floor(max(0.0, float(w - 1)) / 2.0))
	if w >= 7:
		# From wave 7 onward, add another tier every 2 waves (double the speed).
		base += int(floor(float(w - 6) / 2.0))
	base += int(dp.get("tier_bonus", 0))
	return max(1, base)


func _random_spawn_position() -> Vector2:
	if arena_bounds and arena_bounds.has_method("get_arena_rect"):
		var r: Rect2 = arena_bounds.call("get_arena_rect")
		# keep a small margin so spawns are fully inside the walls
		var m: float = 24.0
		var x := randf_range(r.position.x + m, r.position.x + r.size.x - m)
		var y := randf_range(r.position.y + m, r.position.y + r.size.y - m)
		return Vector2(x, y)
	# fallback to viewport center area if bounds missing
	var rect := get_viewport().get_visible_rect()
	var x2 := randf_range(rect.position.x + 16.0, rect.position.x + rect.size.x - 16.0)
	var y2 := randf_range(rect.position.y + 16.0, rect.position.y + rect.size.y - 16.0)
	return Vector2(x2, y2)

func _on_player_died() -> void:
	is_game_over = true
	wave_timer.stop()
	spawn_timer.stop()
	var game_over_label := $UI/CenterContainer/GameOverLabel
	if game_over_label:
		game_over_label.visible = true

func add_score(kills: int, reward_pts: int) -> void:
	# Score reflects number of kills.
	score += kills
	# XP and currency scale with enemy power via reward_pts.
	_gain_xp(reward_pts)
	var mult: float = 1.0
	if player and player.has_method("get"):
		mult = float(player.get("currency_gain_mult"))
	currency_gained_this_wave += int(round(reward_pts * mult))
	# Lifesteal should reflect actual kills, not reward scaling.
	if player and player.lifesteal_per_kill > 0:
		player.heal(player.lifesteal_per_kill * kills)

func _update_ui() -> void:
	if ui_health:
		ui_health.text = "HP: %d" % player.health
	if ui_wave:
		var diff_label := String(difficulty)
		ui_wave.text = "  |  Wave: %d  (%s)" % [wave, diff_label]
	if ui_time:
		ui_time.text = "  |  Time: %d" % int(max(0.0, wave_time - elapsed))
	if ui_score:
		ui_score.text = "  |  Score: %d" % score
	if ui_level:
		var need := _xp_for_next_level(level)
		ui_level.text = "  |  Lv: %d (%d/%d)" % [level, xp, need]
	_update_weapons_hud()

func _update_weapons_hud() -> void:
	var labels: Array = [hud_slot1, hud_slot2, hud_slot3, hud_slot4, hud_slot5, hud_slot6]
	for i in range(labels.size()):
		var text := "%d: --" % (i + 1)
		if i < player.weapons.size():
			var w: Dictionary = player.weapons[i]
			var wname: String = String(w.get("name", "?"))
			var cd: float = float(w.get("cd", 0.0))
			var cd_s: String = ("RDY" if cd <= 0.0 else "%.1fs" % cd)
			# Remove textual tier tag; color indicates tier
			text = "%d: %s  [%s]" % [i + 1, wname, cd_s]
		if labels[i]:
			labels[i].text = text
			var tier_for_color: int = 1
			if i < player.weapons.size():
				tier_for_color = int(player.weapons[i].get("tier", 1))
			var col := _color_for_tier(tier_for_color)
			labels[i].add_theme_color_override("font_color", col)
			# Apply or clear highlight outline
			if _hud_highlight.has(i):
				var hcol: Color = _hud_highlight[i]
				labels[i].add_theme_color_override("font_outline_color", hcol)
				labels[i].add_theme_constant_override("outline_size", 2)
			else:
				labels[i].remove_theme_color_override("font_outline_color")
				labels[i].remove_theme_constant_override("outline_size")

func _highlight_hud_slot(index: int, color: Color) -> void:
	_hud_highlight[index] = color
	_update_weapons_hud()

func _clear_hud_highlights() -> void:
	_hud_highlight.clear()
	_update_weapons_hud()

func _xp_for_next_level(l: int) -> int:
	# Non-linear XP curve: modest early, steeper later
	var lf := float(max(1, l))
	var need := 6.0 + 4.0 * lf + 5.00 * lf * lf
	return max(8, int(round(need)))

func _gain_xp(pts: int) -> void:
	xp += pts
	var need := _xp_for_next_level(level)
	while xp >= need:
		xp -= need
		level += 1
		levels_gained_this_wave += 1
		need = _xp_for_next_level(level)

func begin_intermission() -> void:
	if in_intermission:
		return
	in_intermission = true
	spawn_timer.stop()
	pending_choices = levels_gained_this_wave
	get_tree().paused = true
	_update_stats_panel_visibility()
	if pending_choices > 0:
		_show_upgrade_choices()
	else:
		open_shop()

func _show_upgrade_choices() -> void:
	upgrade_panel.visible = true
	upgrade_title.text = "Choose an upgrade (%d left)" % pending_choices
	current_choices = UpgradeDB.weighted_choices(3)
	var texts: Array[String] = []
	for u in current_choices:
		texts.append(String(u["name"]))
	btn1.text = texts[0]
	btn2.text = texts[1]
	btn3.text = texts[2]
	var r1: String = String(current_choices[0].get("rarity", "Common"))
	var r2: String = String(current_choices[1].get("rarity", "Common"))
	var r3: String = String(current_choices[2].get("rarity", "Common"))
	var c1: Color = ShopLib.rarity_color(r1)
	var c2: Color = ShopLib.rarity_color(r2)
	var c3: Color = ShopLib.rarity_color(r3)
	btn1.add_theme_color_override("font_color", c1)
	btn1.add_theme_color_override("font_hover_color", c1)
	btn1.add_theme_color_override("font_pressed_color", c1)
	btn1.add_theme_color_override("font_focus_color", c1)
	btn2.add_theme_color_override("font_color", c2)
	btn2.add_theme_color_override("font_hover_color", c2)
	btn2.add_theme_color_override("font_pressed_color", c2)
	btn2.add_theme_color_override("font_focus_color", c2)
	btn3.add_theme_color_override("font_color", c3)
	btn3.add_theme_color_override("font_hover_color", c3)
	btn3.add_theme_color_override("font_pressed_color", c3)
	btn3.add_theme_color_override("font_focus_color", c3)
	_refresh_item_summaries()
	_update_stats_panel_visibility()

func _on_option_pressed(index: int) -> void:
	if index >= 0 and index < current_choices.size():
		var upg: Dictionary = current_choices[index]
		if player and player.has_method("apply_upgrade"):
			player.apply_upgrade(upg)
		pending_choices -= 1
		if pending_choices > 0:
			_show_upgrade_choices()
		else:
			upgrade_panel.visible = false
			open_shop()

func open_shop() -> void:
	# Move earned currency to wallet
	currency_total += currency_gained_this_wave
	currency_gained_this_wave = 0
	_generate_shop_offers()
	_show_shop()
	_refresh_item_summaries()
	_update_stats_panel_visibility()

func _generate_shop_offers() -> void:
	# Generate a new set, but preserve any locked, unsold items in their slots.
	var prev: Array[Dictionary] = shop_offers
	var generated: Array[Dictionary] = ShopLib.generate_offers(3, wave)
	# Initialize flags on generated offers
	for i in range(generated.size()):
		generated[i]["sold"] = false
		generated[i]["locked"] = false
	# Overlay locked offers from previous list
	for i in range(min(3, prev.size())):
		var o: Dictionary = prev[i]
		if bool(o.get("locked", false)) and not bool(o.get("sold", false)):
			generated[i] = o
	shop_offers = generated

func _show_shop() -> void:
	shop_panel.visible = true
	_update_shop_title()
	# removed unused variable
	var btns: Array = [shop_opt1, shop_opt2, shop_opt3]
	for i in range(min(3, shop_offers.size())):
		var o: Dictionary = shop_offers[i]
		var sold := bool(o.get("sold", false))
		var locked := bool(o.get("locked", false))
		var display_name: String = String(o.get("name","?"))
		var label := "%s - %d$\n%s" % [display_name, int(o["cost"]), o.get("desc", "")]
		if sold:
			label = "%s\n[SOLD OUT]" % o["name"]
		elif locked:
			label = "[LOCKED] %s" % label
		btns[i].text = label


		btns[i].disabled = sold
		# Color: items by rarity; weapons by tier if >1 otherwise rarity
		var rarity: String = String(o.get("rarity", "Common"))
		var rcol: Color = ShopLib.rarity_color(rarity)
		if String(o.get("kind","")) == "weapon":
			var wtier: int = int(o.get("tier", 1))
			# Always color weapons by tier for consistency with inventory
			rcol = _color_for_tier(wtier)
		if sold:
			rcol = Color(0.6, 0.6, 0.6)
		btns[i].add_theme_color_override("font_color", rcol)
		btns[i].add_theme_color_override("font_hover_color", rcol)
		btns[i].add_theme_color_override("font_pressed_color", rcol)
		btns[i].add_theme_color_override("font_focus_color", rcol)
		# Clear any previous border overrides to avoid stale highlights
		btns[i].remove_theme_stylebox_override("normal")
		btns[i].remove_theme_stylebox_override("hover")
		btns[i].remove_theme_stylebox_override("pressed")
		btns[i].remove_theme_stylebox_override("focus")
		# Subtle blue border for locked items
		if locked and not sold:
			var sbl := StyleBoxFlat.new()
			sbl.draw_center = false
			sbl.border_color = Color(0.4, 0.7, 1.0, 0.95)
			sbl.border_width_left = 3
			sbl.border_width_top = 3
			sbl.border_width_right = 3
			sbl.border_width_bottom = 3
			btns[i].add_theme_stylebox_override("normal", sbl)
			btns[i].add_theme_stylebox_override("hover", sbl)
			btns[i].add_theme_stylebox_override("pressed", sbl)
			btns[i].add_theme_stylebox_override("focus", sbl)
		# Border highlight only for weapons the player already owns (helps spot mergable items)
		if String(o.get("kind","")) == "weapon" and player != null:
			var wid: String = String(o.get("id", ""))
			var wtier: int = int(o.get("tier", 1))
			var owned_total: int = _count_player_weapon(wid)
			var owned_same_tier: int = _count_player_weapon_at_tier(wid, wtier)
			if owned_same_tier >= 2:
				# Green, thicker border when this purchase would cause an immediate merge
				var sb := StyleBoxFlat.new()
				sb.draw_center = false
				sb.border_color = Color(0.3, 1.0, 0.3, 0.95)
				sb.border_width_left = 4
				sb.border_width_top = 4
				sb.border_width_right = 4
				sb.border_width_bottom = 4
				btns[i].add_theme_stylebox_override("normal", sb)
				btns[i].add_theme_stylebox_override("hover", sb)
				btns[i].add_theme_stylebox_override("pressed", sb)
				btns[i].add_theme_stylebox_override("focus", sb)
			elif owned_total > 0:
				# Optional: thin yellow border when owned but not an immediate merge
				var sb2 := StyleBoxFlat.new()
				sb2.draw_center = false
				sb2.border_color = Color(1.0, 1.0, 0.2, 0.9)
				sb2.border_width_left = 2
				sb2.border_width_top = 2
				sb2.border_width_right = 2
				sb2.border_width_bottom = 2
				btns[i].add_theme_stylebox_override("normal", sb2)
				btns[i].add_theme_stylebox_override("hover", sb2)
				btns[i].add_theme_stylebox_override("pressed", sb2)
				btns[i].add_theme_stylebox_override("focus", sb2)
	# If fewer than 3 offers, clear remaining buttons
	for i in range(shop_offers.size(), 3):
		btns[i].text = "--"
		btns[i].disabled = true
	_refresh_item_summaries()

func _update_shop_title() -> void:
	shop_title.text = "Shop - Currency: %d" % currency_total

func _count_player_weapon(id: String) -> int:
	if player == null:
		return 0
	var cnt := 0
	for w in player.weapons:
		if String(w.get("id","")) == id:
			cnt += 1
	return cnt

func _count_player_weapon_at_tier(id: String, tier: int) -> int:
	if player == null:
		return 0
	var cnt := 0
	for w in player.weapons:
		if String(w.get("id","")) == id and int(w.get("tier", 1)) == tier:
			cnt += 1
	return cnt

func _optimize_runtime() -> void:
	# Placeholder for future frame-based adaptations (pooling, LOD, etc.).
	# Current adaptive logic handled in spawn adjustment and projectile/turret scaling.
	pass

## Rarity color now centralized in ShopLib.rarity_color

func _color_for_tier(t: int) -> Color:
	if t <= 1:
		return Color(0.85, 0.85, 0.85)
	elif t == 2:
		return Color(0.4, 1.0, 0.4)
	elif t == 3:
		return Color(0.4, 0.6, 1.0)
	elif t == 4:
		return Color(0.8, 0.4, 1.0)
	elif t == 5:
		return Color(1.0, 0.7, 0.2)
	else:
		return Color(1.0, 0.3, 0.3)

func _on_shop_buy(index: int) -> void:
	if index < 0 or index >= shop_offers.size():
		return
	var offer: Dictionary = shop_offers[index]
	if bool(offer.get("sold", false)):
		return
	var cost: int = int(offer["cost"])
	if currency_total < cost:
		return
	# Check capacity/merge before paying
	if String(offer.get("kind","")) == "weapon":
		if not (player and player.has_method("can_accept_weapon") and player.can_accept_weapon(offer)):
			return
	currency_total -= cost
	var kind: String = String(offer["kind"])
	match kind:
		"weapon":
			if player and player.has_method("equip_weapon"):
				player.equip_weapon(offer)
		"item":
			var item_id: String = String(offer["id"])
			match item_id:
				"money_charm":
					if player:
						player.currency_gain_mult *= 1.2
						player.add_item("money_charm")
				"turret":
					_queue_turret()
					if player:
						player.add_item("turret")
				"scope":
					# Deprecated: bonus projectiles now only come from weapon tiers
					pass
				"overcharger":
					if player:
						if player.has_method("apply_attack_speed_multiplier"):
							player.apply_attack_speed_multiplier(1.15)
						else:
							player.attack_speed_mult *= 1.15
						player.add_item("overcharger")
				"adrenaline":
					if player:
						player.regen_per_second += 0.5
						player.add_item("adrenaline")
				"lifesteal_charm":
					if player:
						player.lifesteal_per_kill += 1
						player.add_item("lifesteal_charm")
				"boots":
					if player:
						if player.has_method("apply_move_speed_multiplier"):
							player.apply_move_speed_multiplier(1.10)
						else:
							player.move_speed *= 1.10
						player.add_item("boots")
				"caffeine":
					if player:
						if player.has_method("apply_attack_speed_multiplier"):
							player.apply_attack_speed_multiplier(1.10)
						else:
							player.attack_speed_mult *= 1.10
						player.add_item("caffeine")
				"ammo_belt":
					# Deprecated: bonus projectiles now only come from weapon tiers
					pass
				"aerodynamics":
					if player:
						player.projectile_speed_mult *= 1.20
						player.add_item("aerodynamics")
				"protein_bar":
					if player:
						player.max_health += 15
						if player.has_method("notify_max_health_changed"):
							player.notify_max_health_changed()
						player.heal(15)
						player.add_item("protein_bar")
				"medkit":
					if player:
						player.regen_per_second += 1.0
						player.add_item("medkit")
				"greed_token":
					if player:
						player.currency_gain_mult *= 1.15
						player.add_item("greed_token")
				"vampiric_orb":
					if player:
						player.lifesteal_per_kill += 1
						player.add_item("vampiric_orb")
				"power_core":
					if player:
						player.damage_mult *= 1.10
						player.add_item("power_core")
				"stabilizer":
					if player:
						player.spread_degrees = max(0.0, player.spread_degrees - 2.0)
						player.add_item("stabilizer")
				"volatile_rounds":
					if player:
						player.add_item("volatile_rounds")
				"elemental_fuse":
					if player:
						player.add_item("elemental_fuse")
				"payload_catalyst":
					if player:
						player.add_item("payload_catalyst")
				"superconductor":
					if player:
						player.add_item("superconductor")
				"turret_servos":
					if player:
						player.turret_projectile_speed_mult *= 1.20
						player.add_item("turret_servos")
				"gyro_stabilizer":
					if player:
						player.turret_projectile_speed_mult *= 1.35
						player.add_item("gyro_stabilizer")
				"toolkit":
					if player:
						player.turret_power_mult *= 1.10
						player.add_item("toolkit")
				"engineer_manual":
					if player:
						player.turret_power_mult *= 1.20
						player.add_item("engineer_manual")
				"heartforge_core":
					if player:
						player.max_health += 25
						player.add_item("heartforge_core")
						if player.has_method("notify_max_health_changed"):
							player.notify_max_health_changed()
						player.heal(25)
				"titan_ward":
					if player:
						player.max_health += 30
						player.add_item("titan_ward")
						if player.has_method("apply_incoming_damage_multiplier"):
							player.apply_incoming_damage_multiplier(0.90)
						else:
							player.incoming_damage_mult = max(0.20, player.incoming_damage_mult * 0.90)
						if player.has_method("notify_max_health_changed"):
							player.notify_max_health_changed()
						player.heal(30)
						if player.has_method("refresh_titan_ward_barrier"):
							player.refresh_titan_ward_barrier()
				"hemorrhage_engine":
					if player:
						player.max_health += 20
						player.add_item("hemorrhage_engine")
						if player.has_method("notify_max_health_changed"):
							player.notify_max_health_changed()
						player.heal(20)
				"blast_caps":
					if player:
						player.explosive_power_mult *= 1.10
						player.add_item("blast_caps")
				"demolition_kit":
					if player:
						player.explosive_power_mult *= 1.15
						player.add_item("demolition_kit")
				"payload_upgrade":
					if player:
						player.explosive_power_mult *= 1.20
						player.add_item("payload_upgrade")
				"warhead":
					if player:
						player.explosive_power_mult *= 1.30
						player.add_item("warhead")
				"elemental_amp":
					if player:
						player.elemental_damage_mult *= 1.10
						player.add_item("elemental_amp")
				"elemental_catalyst":
					if player:
						player.elemental_damage_mult *= 1.20
						player.add_item("elemental_catalyst")
				"elemental_core":
					if player:
						player.elemental_damage_mult *= 1.30
						player.add_item("elemental_core")
				"arcanum":
					if player:
						player.elemental_damage_mult *= 1.40
						player.add_item("arcanum")
				"kevlar_vest":
					if player:
						player.incoming_damage_mult *= 0.90
						player.incoming_damage_mult = max(0.20, player.incoming_damage_mult)
						player.add_item("kevlar_vest")
				"riot_armor":
					if player:
						player.incoming_damage_mult *= 0.85
						player.incoming_damage_mult = max(0.20, player.incoming_damage_mult)
						player.add_item("riot_armor")
				"plated_armor":
					if player:
						player.incoming_damage_mult *= 0.80
						player.incoming_damage_mult = max(0.20, player.incoming_damage_mult)
						player.add_item("plated_armor")
				"nanoshield":
					if player:
						player.incoming_damage_mult *= 0.75
						player.incoming_damage_mult = max(0.20, player.incoming_damage_mult)
						player.add_item("nanoshield")
				_:
					pass
		_:
			pass
	# Mark as sold and disable button to prevent multiple purchases
	shop_offers[index]["sold"] = true
	shop_offers[index]["locked"] = false
	# Immediately refresh HUD and shop UI while paused
	_update_weapons_hud()
	_update_shop_title()
	_show_shop()
	_refresh_item_summaries()

func _on_shop_reroll() -> void:
	var cost := 5
	if currency_total < cost:
		return
	currency_total -= cost
	_generate_shop_offers()
	_show_shop()
	_refresh_item_summaries()

func _on_shop_toggle_lock(index: int) -> void:
	if index < 0 or index >= shop_offers.size():
		return
	if bool(shop_offers[index].get("sold", false)):
		return
	var cur := bool(shop_offers[index].get("locked", false))
	shop_offers[index]["locked"] = not cur
	_show_shop()

func _on_shop_start() -> void:
	shop_panel.visible = false
	get_tree().paused = false
	levels_gained_this_wave = 0
	_clear_hud_highlights()
	_start_next_wave()
	_update_stats_panel_visibility()

func _on_weapon_added(index: int) -> void:
	# Yellow outline for new items
	_highlight_hud_slot(index, Color(1.0, 1.0, 0.2))

func _on_weapon_merged(id: String, tier: int, index: int) -> void:
	_notify_shop("Merged %s to T%d" % [id, tier], _color_for_tier(tier))
	_highlight_hud_slot(index, _color_for_tier(tier))

func _notify_shop(msg: String, col: Color = Color(1,1,1)) -> void:
	var n := $UI/ShopPanel/ShopNotifications if has_node("UI/ShopPanel/ShopNotifications") else null
	if n and n.has_method("show_message"):
		n.call("show_message", msg, col)
	else:
		_notify(msg, col)

func _start_next_wave() -> void:
	wave += 1
	elapsed = 0.0
	in_intermission = false
	if player and player.has_method("refresh_titan_ward_barrier"):
		player.refresh_titan_ward_barrier()
	# Update wave duration with growth per wave, capped at 90s
	wave_time = _compute_wave_duration(wave)
	wave_timer.wait_time = wave_time
	# Pre-wave: place queued turrets and merge before timers start
	_spawn_pending_turrets()
	_balance_turrets()
	_update_ui()
	wave_timer.start()
	# Faster spawn cadence baseline for stronger pressure, scaled by difficulty
	# Start faster and ramp down more aggressively each wave.
	var base_wait: float = max(0.10, 0.80 - float(wave) * 0.10)
	var dp: Dictionary = _difficulty_params()
	var cadence_mult: float = float(dp.get("cadence_mult", 1.0))
	spawn_timer.wait_time = clamp(base_wait * cadence_mult, 0.10, 3.0)
	spawn_timer.start()
	# Spawn a boss every 5th wave (5,10,15,...) once per wave
	if wave % 5 == 0:
		_spawn_boss_for_wave()

# Compute wave duration in seconds, increasing with wave and capped.
func _compute_wave_duration(w: int) -> float:
	var wave_index: int = max(1, w)
	var base_duration: float = 20.0 + 5.0 * float(max(0, wave_index - 1))
	var base_cap: float = 90.0
	var cap_bonus_steps: int = 0
	if wave_index > 20:
		cap_bonus_steps = int(floor(float(wave_index - 20) / 10.0))
	var dynamic_cap: float = base_cap + 10.0 * float(cap_bonus_steps)
	return min(dynamic_cap, base_duration)

func _spawn_boss_for_wave() -> void:
	if BOSS_SCENE == null:
		return
	# Avoid duplicates if one is already alive
	var existing := get_tree().get_nodes_in_group("boss")
	for b in existing:
		if is_instance_valid(b):
			return
	var pos := _random_spawn_position()
	var boss = BOSS_SCENE.instantiate()
	add_child(boss)
	if boss.has_method("activate"):
		boss.call("activate", pos, wave, player)
	else:
		boss.global_position = pos
		if boss.has_method("set_wave"):
			boss.call("set_wave", wave)
		if boss.has_method("add_to_group"):
			boss.add_to_group("boss")

func _balance_turrets() -> void:
	# Merge turrets if too many: combine 3 of same tier into 1 of next tier until <= 5 remain
	var all := get_tree().get_nodes_in_group("turrets")
	var max_allowed := 5
	var total := all.size()
	if total <= max_allowed:
		return
	# Build tier map
	var by_tier := {}
	for t in all:
		var ti := int(t.get("tier")) if t.has_method("get") else 1
		var role := "attack"
		if t.has_method("get"):
			var maybe_role = t.get("turret_role")
			if maybe_role != null:
				role = String(maybe_role)
		var key := "%s|%d" % [role, ti]
		if not by_tier.has(key):
			by_tier[key] = {
				"tier": ti,
				"role": role,
				"nodes": [],
			}
		var entry: Dictionary = by_tier[key]
		var arr: Array = entry["nodes"]
		arr.append(t)
		entry["nodes"] = arr
		by_tier[key] = entry
	var changed := true
	while total > max_allowed and changed:
		changed = false
		for key in by_tier.keys():
			var entry: Dictionary = by_tier[key]
			var arr: Array = entry["nodes"]
			# purge freed nodes
			arr = arr.filter(func(n): return is_instance_valid(n))
			entry["nodes"] = arr
			by_tier[key] = entry
			while arr.size() >= 3 and total > max_allowed:
				# take three, remove them, spawn one upgraded
				var to_merge: Array = [arr.pop_back(), arr.pop_back(), arr.pop_back()]
				for n in to_merge:
					if is_instance_valid(n):
						if turret_pool and turret_pool.has_method("return_turret"):
							turret_pool.call("return_turret", n)
						else:
							n.queue_free()
				total -= 2 # 3 -> 1 reduces by 2
				var pos := player.global_position + Vector2(randf_range(-80,80), randf_range(-80,80))
				var tier_val: int = int(entry.get("tier", 1))
				var role := String(entry.get("role", "attack"))
				_spawn_turret_at_with_tier(pos, tier_val + 1, role)
				var label := "Turrets"
				if role == "healing":
					label = "Healing turrets"
				_notify("%s merged to T%d" % [label, tier_val + 1], Color(0.8, 0.9, 1.0))
				changed = true
			if total <= max_allowed:
				break
		if not changed:
			break

func _spawn_turret_at_with_tier(pos: Vector2, tier: int, mode: String = "attack") -> void:
	if TURRET_SCENE == null:
		return
	if turret_pool and turret_pool.has_method("spawn_turret"):
		turret_pool.call("spawn_turret", pos, tier, mode)
	else:
		var t = TURRET_SCENE.instantiate()
		add_child(t)
		if t.has_method("activate"):
			t.call("activate", pos, tier, null, mode)
		else:
			t.global_position = pos
			if t.has_method("set_tier"):
				t.set_tier(tier)
			if t.has_method("add_to_group"):
				t.add_to_group("turrets")

func _notify(msg: String, col: Color = Color(1,1,1)) -> void:
	var n := $UI/Notifications if has_node("UI/Notifications") else null
	if n and n.has_method("show_message"):
		n.call("show_message", msg, col)

func _as_color(v: Variant) -> Color:
	if v is Color:
		return v
	# Accept common representations; fall back to white
	if v is String:
		# Try parsing hex like "#RRGGBB"; Godot Color can parse some strings, but be safe
		return Color(1,1,1)
	return Color(1,1,1)

func _begin_first_wave_after_character() -> void:
	wave = 0
	awaiting_character = false
	_start_next_wave()

func _show_character_select() -> void:
	# Build options from weapons list (plus Starter)
	character_panel.visible = true
	# Setup difficulty option button
	_setup_difficulty_widget()
	# Clear existing buttons
	for c in char_opts.get_children():
		c.queue_free()
	var chars: Array[Dictionary] = []
	# Starter character
	chars.append({
		"id":"starter","name":"Starter","color": Color(1,1,0.2),
		"weapon": {"kind":"weapon","id":"starter","name":"Starter","fire_interval":0.4,"damage":8,"speed":500.0,"projectiles":1,"color": Color(1,1,0.2)}
	})
	for w in ShopLib.weapons():
		var wcol: Color = _as_color(w.get("color", Color(1,1,1)))
		chars.append({"id": w["id"], "name": w["name"], "color": wcol, "weapon": w})
	# Create a button per character
	for ch in chars:
		var b := Button.new()
		b.text = String(ch["name"]) 
		var col: Color = _as_color(ch.get("color", Color(1,1,1)))
		b.add_theme_color_override("font_color", col)
		b.pressed.connect(Callable(self, "_on_character_chosen").bind(ch))
		char_opts.add_child(b)
	char_title.text = "Choose Your Character"
	# Pause during character selection (original behavior); PausePanel handles ESC to resume.
	get_tree().paused = true

func _on_character_chosen(ch: Dictionary) -> void:
	character_panel.visible = false
	get_tree().paused = false
	in_intermission = false
	if shop_panel:
		shop_panel.visible = false
	if pause_panel:
		pause_panel.visible = false
	# Apply player color and starting weapon
	if player and player.has_method("set_player_color"):
		player.set_player_color(_as_color(ch.get("color", Color(1,1,0.2))))
	if player and player.has_method("equip_weapon"):
		player.weapons.clear()
		player.equip_weapon(Dictionary(ch["weapon"]))
	_begin_first_wave_after_character()

func _setup_difficulty_widget() -> void:
	if char_diff == null:
		return
	char_diff.clear()
	var opts := ["Easy", "Normal", "Hard", "Insane"]
	for i in range(opts.size()):
		char_diff.add_item(opts[i], i)
	# select current difficulty
	var idx := opts.find(String(difficulty))
	if idx == -1:
		idx = 1 # Normal
	char_diff.select(idx)
	# connect change handler once
	if not char_diff.is_connected("item_selected", Callable(self, "_on_difficulty_selected")):
		char_diff.item_selected.connect(_on_difficulty_selected)

func _on_difficulty_selected(index: int) -> void:
	var opts := ["Easy", "Normal", "Hard", "Insane"]
	var idx = clamp(index, 0, opts.size() - 1)
	difficulty = String(opts[idx])
	_update_ui()

@onready var hud_slot1: Label = $UI/WeaponsPanel/VBox/Slot1
@onready var hud_slot2: Label = $UI/WeaponsPanel/VBox/Slot2
@onready var hud_slot3: Label = $UI/WeaponsPanel/VBox/Slot3
@onready var hud_slot4: Label = $UI/WeaponsPanel/VBox/Slot4
@onready var hud_slot5: Label = $UI/WeaponsPanel/VBox/Slot5
@onready var hud_slot6: Label = $UI/WeaponsPanel/VBox/Slot6
func _queue_turret() -> void:
	pending_turrets += 1

func _spawn_pending_turrets() -> void:
	if pending_turrets <= 0:
		return
	for i in range(pending_turrets):
		_spawn_turret_at(player.global_position + Vector2(randf_range(-80,80), randf_range(-80,80)))
	pending_turrets = 0

func _spawn_turret_at(pos: Vector2, mode: String = "attack") -> void:
	_spawn_turret_at_with_tier(pos, 1, mode)
