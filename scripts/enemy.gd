extends CharacterBody2D

@export var move_speed: float = 120.0
@export var max_health: int = 20
@export var contact_damage: int = 10

var health: int
var target: Node2D
var tier: int = 1
var active: bool = true
var pool: Node = null

@onready var hitbox: Area2D = $Hitbox
@onready var poly: Polygon2D = $Polygon2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
    # Add to group only while active (done in activate()).
    _apply_tier()
    health = max_health
    if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
        hitbox.body_entered.connect(_on_hitbox_body_entered)

func set_tier(t: int) -> void:
    tier = max(1, t)
    _apply_tier()
    health = max_health

func _apply_tier() -> void:
    var t: int = max(1, tier)
    var base_hp: int = 20
    var base_dmg: int = 10
    var base_speed: float = 120.0
    var hp: int = base_hp
    var dmg: int = base_dmg
    var spd: float = base_speed
    for i in range(2, t + 1):
        hp = int(round(hp * 1.5))
        dmg = int(round(dmg * 1.25))
        spd *= 0.95
    max_health = hp
    contact_damage = dmg
    move_speed = spd
    var s: float = 1.0 + 0.15 * float(t - 1)
    scale = Vector2(s, s)
    if poly:
        poly.color = Color(1.0, 0.3 + 0.1 * float(t - 1), 0.3)

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
    velocity = dir * move_speed
    move_and_slide()

func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        if get_tree().current_scene and get_tree().current_scene.has_method("add_score"):
            get_tree().current_scene.add_score(1)
        _return_to_pool()

func _on_hitbox_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        if body.has_method("take_damage"):
            body.take_damage(contact_damage)

func activate(pos: Vector2, t: int, tgt: Node2D, p: Node) -> void:
    global_position = pos
    set_tier(t)
    target = tgt
    pool = p
    active = true
    if not is_in_group("enemies"):
        add_to_group("enemies")
    visible = true
    modulate.a = 1.0
    if hitbox:
        hitbox.monitoring = true
    if body_shape:
        body_shape.disabled = false
    if poly:
        poly.visible = true

func deactivate() -> void:
    active = false
    visible = false
    if is_in_group("enemies"):
        remove_from_group("enemies")
    if hitbox:
        hitbox.monitoring = false
    if body_shape:
        body_shape.disabled = true

func _return_to_pool() -> void:
    if pool and pool.has_method("return_enemy"):
        pool.call("return_enemy", self)
    else:
        queue_free()
