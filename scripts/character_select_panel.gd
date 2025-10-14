extends Panel

@onready var options_container: GridContainer = $VBox/Options
@onready var diff_button: OptionButton = $VBox/DifficultyRow/Difficulty

var _buttons: Array[Button] = []
var _focused_index: int = 0
var _focus_diff: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_refresh_buttons()
	visibility_changed.connect(Callable(self, "_on_visibility_changed"))

func _refresh_buttons() -> void:
	_buttons.clear()
	for child in options_container.get_children():
		if child is Button:
			var btn := child as Button
			_buttons.append(btn)
			btn.focus_mode = Control.FOCUS_ALL
			var callable_focus := Callable(self, "_on_button_focus_button").bind(btn)
			if btn.is_connected("focus_entered", callable_focus):
				btn.focus_entered.disconnect(callable_focus)
			btn.focus_entered.connect(callable_focus)
			var callable_hover := Callable(self, "_on_button_hover_button").bind(btn)
			if btn.is_connected("mouse_entered", callable_hover):
				btn.mouse_entered.disconnect(callable_hover)
			btn.mouse_entered.connect(callable_hover)
	if diff_button:
		diff_button.focus_mode = Control.FOCUS_ALL
		if diff_button.is_connected("focus_entered", Callable(self, "_on_diff_focus")):
			diff_button.focus_entered.disconnect(Callable(self, "_on_diff_focus"))
		diff_button.focus_entered.connect(Callable(self, "_on_diff_focus"))
		if diff_button.is_connected("mouse_entered", Callable(self, "_on_diff_hover")):
			diff_button.mouse_entered.disconnect(Callable(self, "_on_diff_hover"))
		diff_button.mouse_entered.connect(Callable(self, "_on_diff_hover"))
	_reset_focus()

func _on_visibility_changed() -> void:
	if visible:
		_refresh_buttons()

func _reset_focus() -> void:
	_focused_index = _find_first_focusable()
	_focus_diff = false
	call_deferred("_apply_focus")

func _apply_focus() -> void:
	if _focus_diff:
		if diff_button and diff_button.visible:
			diff_button.grab_focus()
		return
	if _buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, _buttons.size() - 1)
	var btn := _buttons[_focused_index]
	if btn and _is_focusable(btn):
		btn.grab_focus()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		var main := get_tree().current_scene
		if main and main.has_method("_toggle_pause"):
			main._toggle_pause()
		accept_event()
		return
	if event.is_action_pressed("ui_left"):
		if _focus_diff:
			_adjust_difficulty(-1)
			accept_event()
			return
		_cycle_focus(-1)
		accept_event()
		return
	if event.is_action_pressed("ui_right"):
		if _focus_diff:
			_adjust_difficulty(1)
			accept_event()
			return
		_cycle_focus(1)
		accept_event()
		return
	if event.is_action_pressed("ui_up"):
		_shift_vertical(-1)
		accept_event()
		return
	if event.is_action_pressed("ui_down"):
		_shift_vertical(1)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		_activate_focused()
		accept_event()
		return
	if event.is_action_pressed("shop_start") and _focus_diff:
		# Reuse the same face button to confirm while focused on difficulty.
		_activate_focused()
		accept_event()
		return

func _cycle_focus(delta: int) -> void:
	if _focus_diff:
		_focus_diff = false
		if delta >= 0:
			_focused_index = _find_first_focusable()
		else:
			_focused_index = clamp(_buttons.size() - 1, 0, _buttons.size() - 1)
		_apply_focus()
		return
	if _buttons.is_empty():
		return
	var count := _buttons.size()
	var next_index := _focused_index
	for _i in range(count):
		next_index = (next_index + delta + count) % count
		var btn := _buttons[next_index]
		if _is_focusable(btn):
			_focused_index = next_index
			_apply_focus()
			return

func _shift_vertical(direction: int) -> void:
	if direction < 0:
		# Move up. If already on top row, go to difficulty selector if available.
		var row_offset := _buttons_per_row()
		if _focus_diff:
			return
		if row_offset <= 0:
			return
		var next_index := _focused_index + row_offset * direction
		if next_index < 0:
			if diff_button and diff_button.visible:
				_focus_diff = true
				_apply_focus()
			return
		_focused_index = clamp(next_index, 0, _buttons.size() - 1)
	else:
		# Move down. If currently focusing difficulty, go to first option.
		if _focus_diff:
			_focus_diff = false
			_focused_index = _find_first_focusable()
			_apply_focus()
			return
		var row_offset_down := _buttons_per_row()
		if row_offset_down <= 0:
			return
		var next_index_down := _focused_index + row_offset_down * direction
		if next_index_down >= _buttons.size():
			return
		_focused_index = clamp(next_index_down, 0, _buttons.size() - 1)
	_apply_focus()

func _activate_focused() -> void:
	if _focus_diff:
		if diff_button:
			diff_button.show_popup()
		return
	if _buttons.is_empty():
		return
	_focused_index = clamp(_focused_index, 0, _buttons.size() - 1)
	var btn := _buttons[_focused_index]
	if btn and not btn.disabled:
		btn.emit_signal("pressed")

func _find_first_focusable() -> int:
	if _buttons.is_empty():
		return 0
	for i in range(_buttons.size()):
		if _is_focusable(_buttons[i]):
			return i
	return 0

func _buttons_per_row() -> int:
	if options_container.columns > 0:
		return options_container.columns
	return max(1, int(ceil(sqrt(float(_buttons.size())))))

func _is_focusable(btn: Button) -> bool:
	return btn != null and btn.visible

func _on_button_focus_button(btn: Button) -> void:
	if btn == null:
		return
	var idx := _buttons.find(btn)
	if idx >= 0:
		_focused_index = idx
		_focus_diff = false

func _on_button_hover_button(btn: Button) -> void:
	if btn == null:
		return
	var idx := _buttons.find(btn)
	if idx >= 0:
		_focused_index = idx
		_focus_diff = false

func _on_diff_focus() -> void:
	_focus_diff = true
	if diff_button:
		diff_button.grab_focus()

func _on_diff_hover() -> void:
	_focus_diff = true

func _adjust_difficulty(delta: int) -> void:
	if diff_button == null:
		return
	var count := diff_button.get_item_count()
	if count <= 0:
		return
	var idx := diff_button.selected
	idx = (idx + delta) % count
	if idx < 0:
		idx += count
	diff_button.select(idx)
	diff_button.emit_signal("item_selected", idx)
