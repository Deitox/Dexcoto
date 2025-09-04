extends Area2D

@export var speed: float = 600.0
@export var lifetime: float = 2.0
@export var damage: int = 5
@export var color: Color = Color(1, 1, 0.2)

var direction: Vector2 = Vector2.RIGHT
var _life := 0.0

@onready var poly: Polygon2D = $Polygon2D
var active: bool = false
var pool: Node = null
var effect: Dictionary = {}

func _ready() -> void:
	# Join projectiles group only while active (done in activate()).
	body_entered.connect(_on_body_entered)
	if poly:
		poly.color = color

func _physics_process(delta: float) -> void:
	if not active:
		return
	global_position += direction * speed * delta
	_life += delta
	if _life > lifetime:
		_return_to_pool()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		# Apply elemental effect if supported
		if effect != null and effect is Dictionary and effect.size() > 0:
			if body.has_method("apply_elemental_effect"):
				body.call("apply_elemental_effect", effect, damage, global_position)
		_return_to_pool()

func activate(pos: Vector2, dir: Vector2, spd: float, dmg: int, col: Color, life: float, p: Node, eff: Dictionary = {}) -> void:
	global_position = pos
	direction = dir
	speed = spd
	damage = dmg
	color = col
	lifetime = life
	_life = 0.0
	active = true
	pool = p
	effect = eff if eff != null else {}
	visible = true
	set_deferred("monitoring", true)
	if not is_in_group("projectiles"):
		add_to_group("projectiles")
	if poly:
		poly.color = color

func deactivate() -> void:
	active = false
	visible = false
	set_deferred("monitoring", false)
	if is_in_group("projectiles"):
		remove_from_group("projectiles")

func _return_to_pool() -> void:
	if pool and pool.has_method("return_bullet"):
		pool.call("return_bullet", self)
	else:
		queue_free()
