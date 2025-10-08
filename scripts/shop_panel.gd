extends Panel

@onready var btn1: Button = $VBox/Options/Option1
@onready var btn2: Button = $VBox/Options/Option2
@onready var btn3: Button = $VBox/Options/Option3
@onready var reroll: Button = $VBox/Bottom/Reroll
@onready var start_btn: Button = $VBox/Bottom/StartNext

var _option_buttons: Array[Button] = []
var _focused_index: int = 0

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
	_option_buttons = [btn1, btn2, btn3]
	for i in range(_option_buttons.size()):
		var btn := _option_buttons[i]
		if btn == null:
			continue
		btn.focus_mode = Control.FOCUS_ALL
		btn.focus_entered.connect(Callable(self, "_on_option_focus").bind(i))
		btn.mouse_entered.connect(Callable(self, "_on_option_hover").bind(i))
	visibility_changed.connect(Callable(self, "_on_visibility_changed"))
	_reset_focus()

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
	if not visible:
		return
	# Allow opening the Pause panel via ESC while the shop is visible (tree paused)
	if event.is_action_pressed("ui_cancel"):
		var main := get_tree().current_scene
		if main and main.has_method("_toggle_pause"):
			main._toggle_pause()
		accept_event()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_cycle_focus(-1)
		accept_event()
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_cycle_focus(1)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_activate_focused()
		accept_event()

func _on_visibility_changed() -> void:
	if visible:
		_reset_focus()

func _reset_focus() -> void:
	_focused_index = _find_first_focusable()
	call_deferred("_apply_focus")

func _apply_focus() -> void:
	if _option_buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, _option_buttons.size() - 1)
	var btn := _option_buttons[_focused_index]
	if not _is_button_focusable(btn):
		var fallback := _find_first_focusable()
		_focused_index = fallback
		btn = _option_buttons[_focused_index]
	if btn:
		btn.grab_focus()

func _cycle_focus(delta: int) -> void:
	if _option_buttons.is_empty():
		return
	var count := _option_buttons.size()
	var next_index := _focused_index
	for _i in range(count):
		next_index = (next_index + delta + count) % count
		var candidate := _option_buttons[next_index]
		if _is_button_focusable(candidate):
			_focused_index = next_index
			_apply_focus()
			return
	_apply_focus()

func _activate_focused() -> void:
	if _option_buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, _option_buttons.size() - 1)
	var btn := _option_buttons[_focused_index]
	if btn and not btn.disabled:
		_pick(_focused_index)

func _find_first_focusable() -> int:
	if _option_buttons.is_empty():
		return 0
	for i in range(_option_buttons.size()):
		if _is_button_focusable(_option_buttons[i]):
			return i
	return clamp(_focused_index, 0, _option_buttons.size() - 1)

func _is_button_focusable(btn: Button) -> bool:
	return btn != null and btn.visible

func _on_option_focus(index: int) -> void:
	_focused_index = clamp(index, 0, _option_buttons.size() - 1)

func _on_option_hover(index: int) -> void:
	_focused_index = clamp(index, 0, _option_buttons.size() - 1)
