extends Panel

@onready var btn1: Button = $VBox/Options/Option1
@onready var btn2: Button = $VBox/Options/Option2
@onready var btn3: Button = $VBox/Options/Option3
@onready var reroll: Button = $VBox/Bottom/Reroll
@onready var start_btn: Button = $VBox/Bottom/StartNext

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    btn1.pressed.connect(Callable(self, "_pick").bind(0))
    btn2.pressed.connect(Callable(self, "_pick").bind(1))
    btn3.pressed.connect(Callable(self, "_pick").bind(2))
    reroll.pressed.connect(Callable(self, "_reroll"))
    start_btn.pressed.connect(Callable(self, "_start"))

func _pick(index: int) -> void:
    var main := get_tree().current_scene
    if main and main.has_method("_on_shop_buy"):
        main._on_shop_buy(index)

func _reroll() -> void:
    var main := get_tree().current_scene
    if main and main.has_method("_on_shop_reroll"):
        main._on_shop_reroll()

func _start() -> void:
    var main := get_tree().current_scene
    if main and main.has_method("_on_shop_start"):
        main._on_shop_start()

