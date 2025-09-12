extends Control

@export var debug_stats: bool = false
var _refresh_requested: bool = false
var _size_wait_attempts: int = 0

func _dbg(msg: String) -> void:
	if debug_stats:
		print("[StatsPanel] ", msg)

@onready var _rich: RichTextLabel = $RichText if has_node("RichText") else null
var _host: VBoxContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Respect container-driven layout: if parent is a Container (VBox/HBox/Scroll),
	# don't override anchors. Only force anchors when free-floating.
	var parent_is_container := get_parent() is Container
	if not parent_is_container:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_dbg("_ready: parent_is_container=%s paused=%s" % [str(parent_is_container), str(get_tree().paused)])
	_fix_parent_layout()

	# Listen for visibility changes on self and ancestors (VBox, Panel)
	_connect_visibility_chain()

	_ensure_host()
	_fix_scroll_layout()
	set_process(true)
	# Defer initial refresh to allow Player to enter groups in Main._ready
	call_deferred("refresh")

func _on_visibility_changed() -> void:
	var vtree := is_visible_in_tree()
	_dbg("visibility_changed: is_visible_in_tree=%s (visible=%s)" % [str(vtree), str(visible)])
	if vtree:
		_fix_parent_layout()
		_fix_scroll_layout()
		_request_refresh()

# Helpers for formatting
static func _pct(v: float) -> String:
	return "%+d%%" % int(round((v - 1.0) * 100.0))

static func _deg(v: float) -> String:
	var deg := char(0x00B0)
	return "%.1f%s" % [v, deg]

# Tier color helpers for headers (matches main.gd palette)
static func _tier_hex(t: int) -> String:
	var c := Color(1,1,1)
	if t <= 1:
		c = Color(0.85, 0.85, 0.85)
	elif t == 2:
		c = Color(0.4, 1.0, 0.4)
	elif t == 3:
		c = Color(0.4, 0.6, 1.0)
	elif t == 4:
		c = Color(0.8, 0.4, 1.0)
	elif t == 5:
		c = Color(1.0, 0.7, 0.2)
	else:
		c = Color(1.0, 0.3, 0.3)
	return c.to_html(false)

func refresh() -> void:
	_dbg("refresh() called; paused=%s visible_in_tree=%s" % [str(get_tree().paused), str(is_visible_in_tree())])
	if not is_visible_in_tree():
		_dbg("skip refresh: not visible in tree")
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		player = _find_player_fallback()
	if player == null:
		_dbg("No player found; clearing host and showing placeholder")
		_ensure_host()
		_clear_host()
		# Visual placeholder to verify the panel renders even when no player
		var placeholder := Label.new()
		placeholder.text = "No player found"
		_host.add_child(placeholder)
		return

	var bullet_pool = get_tree().get_first_node_in_group("bullet_pool")
	if _rich:
		_rich.visible = false
	_ensure_host()
	if _host == null:
		push_error("StatsPanel: _ensure_host() failed to resolve Host")
		return
	_dbg("Using Host at path=%s child_count(before)=%d" % [_host.get_path(), _host.get_child_count()])

	# If layout hasn't been sized yet, defer briefly to let containers assign size.
	var scroll_ctrl: Control = get_node_or_null("Scroll") as Control
	if scroll_ctrl and (scroll_ctrl.size.y <= 0.0 or size.y <= 0.0):
		if _size_wait_attempts < 5:
			_size_wait_attempts += 1
			_dbg("deferring refresh for layout (attempt %d), stats.size=%s scroll.size=%s" % [_size_wait_attempts, str(size), str(scroll_ctrl.size)])
			call_deferred("refresh")
			return
		else:
			_dbg("continuing despite zero size after attempts")

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
	var elemental_power: float = float(player.get("elemental_damage_mult")) if player.has_method("get") else 1.0
	var explosive_power: float = float(player.get("explosive_power_mult")) if player.has_method("get") else 1.0

	var beam_threshold: float = 900.0
	if bullet_pool and bullet_pool.has_method("get_beam_threshold"):
		beam_threshold = float(bullet_pool.call("get_beam_threshold"))

	var as_overflow_mult: float = float(player.get("overflow_damage_mult_from_attack_speed")) if player.has_method("get") else 1.0
	var proj_overflow_mult: float = float(player.get("overflow_damage_mult_from_projectiles")) if player.has_method("get") else 1.0
	var move_overflow_mult: float = float(player.get("overflow_currency_mult_from_move_speed")) if player.has_method("get") else 1.0

	# Beam conversion overflow from projectile speed (estimate using fastest equipped weapon)
	var beam_overflow_mult: float = 1.0
	if bullet_pool and bullet_pool.has_method("get_beam_threshold") and player and player.has_method("get"):
		var thresh: float = float(bullet_pool.call("get_beam_threshold"))
		var psm: float = float(player.get("projectile_speed_mult"))
		var max_speed: float = 0.0
		var wlist = player.get("weapons")
		if typeof(wlist) == TYPE_ARRAY:
			for w in wlist:
				if w is Dictionary and w.has("speed"):
					var s: float = float(w["speed"]) * psm
					if s > max_speed:
						max_speed = s
		if max_speed > thresh and thresh > 0.0:
			beam_overflow_mult = max(1.0, max_speed / thresh)

	# Build grids in the Host container
	_clear_host()
	var _row_count := 0

	# Core
	_add_section_header("Core", _tier_hex(1))
	var core := _add_grid()
	_add_kv(core, "Health", "%d/%d" % [hp, hp_max])
	_add_kv(core, "Regen", "%.1f/s" % regen)
	# Move speed with cap color when at cap (3x base)
	var base_ms: float = float(player.get("base_move_speed")) if player.has_method("get") else move_spd
	var ms_cap_mult: float = float(player.MAX_MOVE_SPEED_MULT)
	var ms_cap_speed: float = base_ms * ms_cap_mult
	var ms_col: Color = Color.WHITE
	if move_spd >= ms_cap_speed - 0.01:
		ms_col = Color("#ff7043")
	_add_kv(core, "Move Speed", "%.0f px/s" % move_spd, ms_col)
	# Defense / Damage taken multiplier
	var dmg_taken_mult: float = float(player.get("incoming_damage_mult")) if player.has_method("get") else 1.0
	if abs(dmg_taken_mult - 1.0) > 0.001:
		_add_kv(core, "Damage Taken", "x%.2f (%s)" % [dmg_taken_mult, _pct(dmg_taken_mult)])

	# Offense
	_add_section_header("Offense", _tier_hex(3))
	var off := _add_grid()
	_add_kv(off, "Damage", "x%.2f (%s)" % [dmg_mult, _pct(dmg_mult)])
	# Crit stats
	var crit_ch: float = float(player.get("crit_chance")) if player.has_method("get") else 0.0
	var crit_dm: float = float(player.get("crit_damage_mult")) if player.has_method("get") else 1.5
	var extra_cc: float = max(0.0, crit_ch - 1.0)
	var show_crit: bool = crit_ch > 0.0 or crit_dm > 1.0
	if show_crit:
		var cc_text := "%.0f%%" % (min(crit_ch, 1.0) * 100.0)
		if extra_cc > 0.0:
			cc_text += " (cap 100%)"
		_add_kv(off, "Crit Chance", cc_text)
		var cd_text := "x%.2f" % (crit_dm + extra_cc)
		if extra_cc > 0.0:
			cd_text += " (+%.2f overflow)" % extra_cc
		_add_kv(off, "Crit Damage", cd_text)
	var as_col: Color = Color.WHITE
	if atk_mult >= atk_cap:
		as_col = Color("#ff7043")
	elif atk_mult >= atk_cap * 0.9:
		as_col = Color("#ffb74d")
	# Split long Attack Speed details into separate aligned rows to avoid clipping
	_add_kv(off, "Attack Speed", "x%.2f" % atk_mult, as_col)
	_add_kv(off, "Min Interval", "%.2fs" % min_interval)
	_add_kv(off, "Spread", _deg(spread_deg))

	# Projectiles
	_add_section_header("Projectiles", _tier_hex(2))
	var proj := _add_grid()
	var proj_col: Color = Color("#ff7043") if proj_bonus >= proj_cap else Color.WHITE
	_add_kv(proj, "Bonus Projectiles", "+%d (cap +%d)" % [proj_bonus, proj_cap], proj_col)
	_add_kv(proj, "Projectile Speed", "x%.2f" % proj_speed_mult)
	_add_kv(proj, "Per-shot cap", "%d" % per_shot_cap)
	_add_kv(proj, "Global soft cap", "%d" % soft_proj_cap)
	_add_kv(proj, "Beam threshold", "%.0f px/s" % beam_threshold)

	# Overflows consolidated
	if as_overflow_mult > 1.0 or proj_overflow_mult > 1.0 or move_overflow_mult > 1.0 or beam_overflow_mult > 1.0:
		_add_section_header("Overflows", _tier_hex(5))
		var ov := _add_grid()
		if as_overflow_mult > 1.0:
			_add_kv(ov, "Attack Speed -> Damage", _pct(as_overflow_mult), Color("#66bb6a"))
		if proj_overflow_mult > 1.0:
			_add_kv(ov, "Projectiles -> Damage", _pct(proj_overflow_mult), Color("#66bb6a"))
		if move_overflow_mult > 1.0:
			_add_kv(ov, "Move Speed -> Currency", _pct(move_overflow_mult), Color("#66bb6a"))
		if beam_overflow_mult > 1.0:
			_add_kv(ov, "Proj Speed -> Beam Dmg", _pct(beam_overflow_mult), Color("#66bb6a"))

	# Powers
	var show_elem: bool = abs(elemental_power - 1.0) > 0.001
	var show_expl: bool = abs(explosive_power - 1.0) > 0.001
	var turret_power: float = float(player.get("turret_power_mult")) if player.has_method("get") else 1.0
	var show_turret: bool = abs(turret_power - 1.0) > 0.001
	if show_elem or show_expl or show_turret:
		_add_section_header("Powers", _tier_hex(4))
		var pwr := _add_grid()
		if show_elem:
			_add_kv(pwr, "Elemental Power", "x%.2f (%s)" % [elemental_power, _pct(elemental_power)])
		if show_expl:
			_add_kv(pwr, "Explosive Power", "x%.2f (%s)" % [explosive_power, _pct(explosive_power)])
		if show_turret:
			_add_kv(pwr, "Turret Power", "x%.2f (%s)" % [turret_power, _pct(turret_power)])

	# Economy
	if abs(currency_mult - 1.0) > 0.001 or lifesteal > 0:
		_add_section_header("Economy", _tier_hex(5))
		var eco := _add_grid()
		if abs(currency_mult - 1.0) > 0.001:
			_add_kv(eco, "Currency Gain", "x%.2f (%s)" % [currency_mult, _pct(currency_mult)])
		if lifesteal > 0:
			_add_kv(eco, "Lifesteal", "+%d HP/kill" % lifesteal)
	_dbg("refresh() built UI; host_children=%d size=%s min_size=%s visible=%s" % [_host.get_child_count(), str(_host.size), str(_host.get_minimum_size()), str(_host.is_visible_in_tree())])
	_size_wait_attempts = 0
	if debug_stats:
		call_deferred("_post_build_layout_check")

func _post_build_layout_check() -> void:
	await get_tree().process_frame
	if _host:
		_dbg("post-frame: host size=%s min_size=%s visible_in_tree=%s" % [str(_host.size), str(_host.get_minimum_size()), str(_host.is_visible_in_tree())])
		var scroll := get_node_or_null("Scroll")
		if scroll:
			_dbg("post-frame: scroll size=%s" % str((scroll as Control).size))
		_dbg("post-frame: stats node size=%s" % str(size))
		# Dump first-level children for quick inspection
		var idx := 0
		for ch in _host.get_children():
			if ch is Control:
				var c := ch as Control
				_dbg("child[%d]=%s size=%s min=%s" % [idx, ch.get_class(), str(c.size), str(c.get_minimum_size())])
			else:
				_dbg("child[%d]=%s" % [idx, ch.get_class()])
			idx += 1

func _connect_visibility_chain() -> void:
	var n: Node = self
	var c := Callable(self, "_on_visibility_changed")
	while n:
		if n.has_signal("visibility_changed") and not n.is_connected("visibility_changed", c):
			n.visibility_changed.connect(c)
			_dbg("connected visibility_changed on %s" % n.name)
		if n.get_parent() == null or n is CanvasLayer:
			break
		n = n.get_parent()

func _fix_parent_layout() -> void:
	# Make sure the VBox container under StatsPanel fills the panel with 8px margins.
	var vb := get_parent() as VBoxContainer
	if vb:
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 8
		vb.offset_top = 8
		vb.offset_right = -8
		vb.offset_bottom = -8
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _request_refresh() -> void:
	if _refresh_requested:
		return
	_refresh_requested = true
	call_deferred("_do_deferred_refresh")

func _do_deferred_refresh() -> void:
	_refresh_requested = false
	refresh()

func _find_player_fallback() -> Node:
	# Try common locations if group lookup failed (e.g., order of _ready callbacks)
	if has_node("/root/Main/Player"):
		return get_node("/root/Main/Player")
	# Search by name as a last resort
	var root := get_tree().root
	if root:
		var found = root.find_child("Player", true, false)
		if found:
			return found
	return null

var _accum: float = 0.0
const REFRESH_INTERVAL := 0.5

func _process(delta: float) -> void:
	# Light auto-refresh while visible to keep numbers current
	if not is_visible_in_tree():
		_accum = 0.0
		return
	_accum += delta
	if _accum >= REFRESH_INTERVAL:
		_accum = 0.0
		refresh()

# Container helpers
func _ensure_host() -> void:
	# Prefer the Host under the ScrollContainer provided by the scene.
	if _host and is_instance_valid(_host):
		return
	if has_node("Scroll/Host"):
		_host = get_node("Scroll/Host") as VBoxContainer
		_dbg("Resolved Host via Scroll/Host")
	elif has_node("Host"):
		# Backward compatibility with older scene layout
		_host = get_node("Host") as VBoxContainer
		_dbg("Resolved Host via direct Host child")
	else:
		# Safe fallback: create Scroll + Host so sizing/scrolling behave as expected
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(scroll)

		_host = VBoxContainer.new()
		_host.name = "Host"
		_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(_host)
		_dbg("Created fallback Scroll + Host")

	# Let container manage Host sizing; just set size flags and spacing.
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.add_theme_constant_override("separation", 8)
	_fix_scroll_layout()

func _fix_scroll_layout() -> void:
	var scroll := get_node_or_null("Scroll") as ScrollContainer
	if scroll:
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 0
		scroll.offset_top = 0
		scroll.offset_right = 0
		scroll.offset_bottom = 0
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _clear_host() -> void:
	if _host == null:
		return
	_dbg("Clearing Host; children=%d" % _host.get_child_count())
	for c in _host.get_children():
		c.queue_free()

func _add_header(title: String, col: Color) -> void:
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", col)
	_host.add_child(l)

func _add_section_header(title: String, hex: String) -> void:
	# Add a small spacer before each section (except when empty)
	if _host.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		_host.add_child(spacer)
	var l := Label.new()
	l.text = title
	l.add_theme_color_override("font_color", Color.from_string("#" + hex, Color.WHITE))
	l.add_theme_font_size_override("font_size", 16)
	_host.add_child(l)
	# Thin separator for readability
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.modulate = Color(1,1,1,0.35)
	_host.add_child(sep)

func _add_grid() -> Container:
	# Use a vertical stack; each KV will be an HBox row inside this stack.
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	_host.add_child(v)
	return v

func _add_kv(stack: Container, key: String, val: String, val_color: Color = Color.WHITE) -> void:
	# Responsive row: [key][spacer][value] so value aligns to the right edge.
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var lk := Label.new()
	lk.text = key
	lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lk.custom_minimum_size = Vector2(140, 0)
	lk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lv := Label.new()
	lv.text = val
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.add_theme_color_override("font_color", val_color)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(lk)
	row.add_child(spacer)
	row.add_child(lv)

	stack.add_child(row)
