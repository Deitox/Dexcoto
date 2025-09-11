extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")

var pool: Array = []

func _ready() -> void:
	add_to_group("enemy_pool")

func spawn_enemy(pos: Vector2, tier: int, target: Node2D) -> Node:
	var e: Node = null
	if pool.size() > 0:
		e = pool.pop_back()
	else:
		e = enemy_scene.instantiate()
		add_child(e)
	if e.has_method("activate"):
		e.call("activate", pos, tier, target, self)
	return e

# Visual pre-spawn cue and delayed activation
func spawn_enemy_telegraphed(pos: Vector2, tier: int, target: Node2D, delay: float = 0.6) -> void:
	_show_telegraph(pos, tier)
	var tmr := get_tree().create_timer(max(0.0, delay))
	tmr.timeout.connect(Callable(self, "spawn_enemy").bind(pos, tier, target))

# Spawn a small group with slight stagger between activations
func spawn_enemy_group(positions: Array, tier: int, target: Node2D, base_delay: float = 0.6, stagger: float = 0.12) -> void:
	for i in range(positions.size()):
		var pos: Vector2 = positions[i]
		var d: float = max(0.0, base_delay + float(i) * max(0.0, stagger))
		spawn_enemy_telegraphed(pos, tier, target, d)

func _show_telegraph(pos: Vector2, tier: int) -> void:
	var ring := Line2D.new()
	ring.width = 3.0
	# Color hint by tier (light red/orange)
	var base_col := Color(1.0, 0.5 + 0.08 * float(max(0, tier - 1)), 0.4, 0.9)
	ring.default_color = base_col
	ring.z_index = 2000
	# Generate a simple circle
	var r: float = 18.0
	var segs: int = 24
	var pts := PackedVector2Array()
	for s in range(segs + 1):
		var a := TAU * float(s) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	ring.points = pts
	add_child(ring)
	ring.global_position = pos
	# Animate radius/alpha then free
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.6)
	tw.tween_callback(ring.queue_free)

func return_enemy(e: Node) -> void:
	if not is_instance_valid(e):
		return
	if e.has_method("deactivate"):
		e.call("deactivate")
	pool.append(e)
