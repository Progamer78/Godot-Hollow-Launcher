extends Node2D

var count := 0
var elapsed := 0.0
var label: Label
var proof_mode := false
var clicked := false

func _ready() -> void:
	proof_mode = "--player-proof" in OS.get_cmdline_user_args()
	var file := ConfigFile.new()
	if file.load("user://proof.cfg") == OK:
		count = int(file.get_value("counter", "value", 0))
	print("PLAYER_PROOF counter loaded=", count, " user=", OS.get_user_data_dir())
	# Same filename as the movement game, deliberately different project/settings.
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 26)
	add_child(label)
	var button := Button.new()
	button.text = "Count and save"
	button.position = Vector2(24, 120)
	button.pressed.connect(_increment)
	add_child(button)
	if proof_mode:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = true
		Input.parse_input_event(key)

func _increment() -> void:
	clicked = true
	count += 1
	var file := ConfigFile.new()
	file.set_value("counter", "value", count)
	var error := file.save("user://proof.cfg")
	if error != OK:
		push_error("Counter save failed: %s" % error)
		return
	print("PLAYER_PROOF counter saved=", count)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_increment()

func _process(delta: float) -> void:
	elapsed += delta
	label.text = "INDEPENDENT COUNTER — Enter / touch button\nSaved count: %d" % count
	queue_redraw()
	if proof_mode and elapsed > 0.4:
		assert(clicked)
		print("PLAYER_PROOF counter PASS input animation saves")
		get_tree().quit()

func _draw() -> void:
	var center := Vector2(480, 320)
	draw_line(center, center + Vector2(cos(elapsed * 3), sin(elapsed * 3)) * 100, Color.ORANGE, 12)
