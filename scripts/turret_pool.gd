extends Node2D

@export var turret_scene: PackedScene = preload("res://scenes/Turret.tscn")

var pool: Array = []

func _ready() -> void:
	add_to_group("turret_pool")

func spawn_turret(pos: Vector2, tier: int) -> Node:
	var t: Node = null
	if pool.size() > 0:
		t = pool.pop_back()
	else:
		t = turret_scene.instantiate()
		add_child(t)
	if t.has_method("activate"):
		t.call("activate", pos, tier, self)
	return t

func return_turret(t: Node) -> void:
	if not is_instance_valid(t):
		return
	if t.has_method("deactivate"):
		t.call("deactivate")
	pool.append(t)
