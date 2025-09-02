extends Node2D

@export var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

var pool: Array = []

func _ready() -> void:
    add_to_group("bullet_pool")

func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, color: Color, lifetime: float = 2.0) -> Node:
    var b: Node = null
    if pool.size() > 0:
        b = pool.pop_back()
    else:
        b = bullet_scene.instantiate()
        add_child(b)
    if b.has_method("activate"):
        b.call("activate", pos, dir, speed, damage, color, lifetime, self)
    return b

func return_bullet(b: Node) -> void:
    if not is_instance_valid(b):
        return
    if b.has_method("deactivate"):
        b.call("deactivate")
    pool.append(b)
