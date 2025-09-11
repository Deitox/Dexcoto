extends CharacterBody2D

@export var base_move_speed: float = 90.0
@export var base_max_health: int = 300
@export var base_contact_damage: int = 25

var health: int
var target: Node2D
var wave_index: int = 1
var active: bool = true
var reward_points: int = 10

@onready var hitbox: Area2D = $Hitbox
@onready var poly: Polygon2D = $Polygon2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_apply_wave_scaling()
	health = max(1, base_max_health)
	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)

func set_wave(w: int) -> void:
	wave_index = max(1, w)
	_apply_wave_scaling()
	health = base_max_health

func _apply_wave_scaling() -> void:
	var w: int = max(1, wave_index)
	# Boss scaling by wave: roughly exponential hp growth, mild damage growth
	var w_scale: float = float(w - 1) / 5.0
	var hp := int(round(float(base_max_health) * pow(1.35, w_scale)))
	var dmg := int(round(float(base_contact_damage) * (1.0 + 0.12 * w_scale)))
	base_max_health = max(1, hp)
	base_contact_damage = max(1, dmg)
	# Size and color cue
	var s: float = 1.6 + 0.05 * w_scale
	scale = Vector2(s, s)
	if poly:
		poly.color = Color(0.6, 0.2, 1.0)
	# Compute rewards higher than regular enemies
	var hp_factor: float = float(base_max_health) / 20.0
	var dmg_factor: float = float(base_contact_damage) / 10.0
	reward_points = max(10, int(round(hp_factor * 0.9 + dmg_factor * 0.4)))

func _physics_process(_delta: float) -> void:
	if not active:
		return
	if target == null or not is_instance_valid(target):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
		else:
			return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	velocity = dir * base_move_speed
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		if get_tree().current_scene and get_tree().current_scene.has_method("add_score"):
			get_tree().current_scene.add_score(1, reward_points)
		queue_free()

func _on_hitbox_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(base_contact_damage)

func activate(pos: Vector2, wave: int, tgt: Node2D) -> void:
	global_position = pos
	set_wave(wave)
	target = tgt
	active = true
	if not is_in_group("enemies"):
		add_to_group("enemies")
	if not is_in_group("boss"):
		add_to_group("boss")
	visible = true
	modulate.a = 1.0
	if hitbox:
		hitbox.set_deferred("monitoring", true)
	if body_shape:
		body_shape.set_deferred("disabled", false)
	if poly:
		poly.visible = true

# Visual hit feedback: floating numbers for boss
func show_damage_feedback(amount: int, is_crit: bool, at: Vector2, custom_color: Color = Color(0,0,0,0), font_size: int = -1) -> void:
	var label := Label.new()
	label.text = str(amount)
	var fsize := 26 if is_crit else 20
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
	label.global_position = at + Vector2(randf_range(-6,6), -12)
	label.z_index = 3000
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 18.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.32)
	tw.tween_callback(label.queue_free)
