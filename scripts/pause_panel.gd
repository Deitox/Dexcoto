extends Panel

@onready var option_buttons: Array[Button] = [
	$VBox/Resume,
	$VBox/Restart,
	$VBox/Quit,
]

var _focused_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_reset_focus()

func _input(event: InputEvent) -> void:
	# Handle ESC even if GUI might consume it; only when panel is visible
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		var main := get_tree().current_scene
		if main and main.has_method("_on_pause_resume"):
			main._on_pause_resume()
		elif main and main.has_method("_toggle_pause"):
			main._toggle_pause()
		accept_event()
		return
	if event.is_action_pressed("shop_start"):
		# Same button as Start Next resumes the game.
		var main2 := get_tree().current_scene
		if main2 and main2.has_method("_on_pause_resume"):
			main2._on_pause_resume()
		elif main2 and main2.has_method("_toggle_pause"):
			main2._toggle_pause()
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

func _reset_focus() -> void:
	_focused_index = _find_first_focusable()
	call_deferred("_apply_focus")

func _apply_focus() -> void:
	if option_buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, option_buttons.size() - 1)
	var btn := option_buttons[_focused_index]
	if btn and btn.visible:
		btn.grab_focus()

func _cycle_focus(delta: int) -> void:
	if option_buttons.is_empty():
		return
	var count := option_buttons.size()
	var next_index := _focused_index
	for _i in range(count):
		next_index = (next_index + delta + count) % count
		var btn := option_buttons[next_index]
		if btn and btn.visible and not btn.disabled:
			_focused_index = next_index
			_apply_focus()
			return
	_apply_focus()

func _activate_focused() -> void:
	if option_buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, option_buttons.size() - 1)
	var btn := option_buttons[_focused_index]
	if btn and btn.visible and not btn.disabled:
		btn.emit_signal("pressed")

func _find_first_focusable() -> int:
	if option_buttons.is_empty():
		return 0
	for i in range(option_buttons.size()):
		var btn := option_buttons[i]
		if btn and btn.visible and not btn.disabled:
			return i
	return clamp(_focused_index, 0, option_buttons.size() - 1)
