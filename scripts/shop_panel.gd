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
	# Right-click to lock/unlock an offer
	btn1.gui_input.connect(Callable(self, "_offer_gui_input").bind(0))
	btn2.gui_input.connect(Callable(self, "_offer_gui_input").bind(1))
	btn3.gui_input.connect(Callable(self, "_offer_gui_input").bind(2))
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

func _offer_gui_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		var main := get_tree().current_scene
		if main and main.has_method("_on_shop_toggle_lock"):
			main._on_shop_toggle_lock(index)

func _input(event: InputEvent) -> void:
	# Allow opening the Pause panel via ESC while the shop is visible (tree paused)
	if event.is_action_pressed("ui_cancel"):
		var main := get_tree().current_scene
		if main and main.has_method("_toggle_pause"):
			main._toggle_pause()
		accept_event()
