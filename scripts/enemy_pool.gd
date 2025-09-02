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

func return_enemy(e: Node) -> void:
    if not is_instance_valid(e):
        return
    if e.has_method("deactivate"):
        e.call("deactivate")
    pool.append(e)
