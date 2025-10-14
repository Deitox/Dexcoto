extends Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

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
		var main2 := get_tree().current_scene
		if main2 and main2.has_method("_on_pause_resume"):
			main2._on_pause_resume()
		elif main2 and main2.has_method("_toggle_pause"):
			main2._toggle_pause()
		accept_event()
