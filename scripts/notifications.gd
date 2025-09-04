extends Control

func show_message(text: String, color: Color = Color(1,1,1)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.modulate = Color(1,1,1,0)
	$VBox.add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)

