extends Panel

@onready var btn1: Button = $VBox/Options/Option1
@onready var btn2: Button = $VBox/Options/Option2
@onready var btn3: Button = $VBox/Options/Option3

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    btn1.pressed.connect(Callable(self, "_pick").bind(0))
    btn2.pressed.connect(Callable(self, "_pick").bind(1))
    btn3.pressed.connect(Callable(self, "_pick").bind(2))

func _pick(index: int) -> void:
    var main := get_tree().current_scene
    if main and main.has_method("_on_option_pressed"):
        main._on_option_pressed(index)
