extends Node2D

@export var fire_interval: float = 0.8
@export var damage: int = 6
@export var speed: float = 480.0
@export var range: float = 420.0
@export var color: Color = Color(0.7, 1.0, 0.3)

var tier: int = 1
var _cd: float = 0.0
@onready var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
@onready var bullet_pool: Node = null
var active: bool = true
var pool: Node = null

func _ready() -> void:
    add_to_group("turrets")
    _apply_tier()
    bullet_pool = get_tree().get_first_node_in_group("bullet_pool")

func set_tier(t: int) -> void:
    tier = max(1, t)
    _apply_tier()

func _apply_tier() -> void:
    # Scale stats by tier: similar to weapons
    var t: int = max(1, tier)
    var base_fire: float = 0.8
    var base_damage: int = 6
    var base_speed: float = 480.0
    var base_range: float = 420.0
    var fi: float = base_fire
    var dmg: int = base_damage
    var proj_speed: float = base_speed
    var rng: float = base_range
    for i in range(2, t + 1):
        dmg = int(round(dmg * 1.25))
        fi *= 0.9
        rng *= 1.05
    fire_interval = fi
    damage = dmg
    speed = proj_speed
    range = rng
    # Make turret slightly larger per tier
    var s: float = 1.0 + 0.1 * float(t - 1)
    scale = Vector2(s, s)

func _physics_process(delta: float) -> void:
    if not active:
        return
    _cd -= delta
    if _cd <= 0.0:
        var target: Node2D = _get_nearest_enemy_in_range()
        if target:
            _shoot(target.global_position)
            _cd = fire_interval

func _get_nearest_enemy_in_range() -> Node2D:
    var enemies: Array = get_tree().get_nodes_in_group("enemies")
    var nearest: Node2D = null
    var min_d: float = range * range
    for e in enemies:
        if is_instance_valid(e):
            var d: float = global_position.distance_squared_to(e.global_position)
            if d < min_d:
                min_d = d
                nearest = e
    return nearest

func _shoot(pos: Vector2) -> void:
    var dir: Vector2 = (pos - global_position).normalized()
    # Projectiles overload control
    var current: int = get_tree().get_nodes_in_group("projectiles").size()
    var soft_cap: int = 200
    var scale_factor: float = 1.0
    if current > soft_cap:
        scale_factor = clamp(float(soft_cap) / float(current), 0.3, 1.0)
    var dmg := int(round(damage * (1.0 / scale_factor)))
    if bullet_pool and bullet_pool.has_method("spawn_bullet"):
        bullet_pool.call("spawn_bullet", global_position + dir * 16.0, dir, speed, dmg, color, 2.0)
    else:
        var b = bullet_scene.instantiate()
        get_tree().current_scene.add_child(b)
        if b.has_method("activate"):
            b.call("activate", global_position + dir * 16.0, dir, speed, dmg, color, 2.0, null)
        else:
            b.global_position = global_position + dir * 16.0
            b.direction = dir
            b.speed = speed
            b.damage = dmg
            b.color = color

func activate(pos: Vector2, t: int, p: Node) -> void:
    global_position = pos
    set_tier(t)
    pool = p
    active = true
    visible = true

func deactivate() -> void:
    active = false
    visible = false
