extends Node2D

var position_on_screen := Vector2(480, 270)
var elapsed := 0.0
var moves := 0
var label: Label
var proof_mode := false

func _ready() -> void:
	proof_mode = "--player-proof" in OS.get_cmdline_user_args()
	var save := ConfigFile.new()
	if save.load("user://proof.cfg") == OK:
		moves = int(save.get_value("game", "moves", 0))
	print("PLAYER_PROOF movement loaded=", moves, " autoload=", Proof.marker, " user=", OS.get_user_data_dir())
	assert(Proof.marker == "movement-autoload")
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)
	var button := Button.new()
	button.text = "Save a move"
	button.position = Vector2(24, 110)
	button.pressed.connect(_save_move)
	add_child(button)
	if proof_mode:
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.pressed = true
		Input.parse_input_event(key)
		_save_move()

func _save_move() -> void:
	moves += 1
	var save := ConfigFile.new()
	save.set_value("game", "moves", moves)
	var error := save.save("user://proof.cfg")
	if error != OK:
		push_error("Movement save failed: %s" % error)
		return
	print("PLAYER_PROOF movement saved=", moves)

func _process(delta: float) -> void:
	elapsed += delta
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	position_on_screen += direction * delta * 180.0
	position_on_screen.x = clampf(position_on_screen.x, 30, 930)
	position_on_screen.y = clampf(position_on_screen.y, 160, 510)
	label.text = "MOVEMENT PROOF — arrows / touch button\nSaved moves: %d · Native GDScript + autoload" % moves
	queue_redraw()
	if proof_mode and elapsed > 0.4:
		assert(position_on_screen.x > 480)
		print("PLAYER_PROOF movement PASS input animation saves")
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_save_move()

func _draw() -> void:
	draw_circle(position_on_screen, 24 + sin(elapsed * 4) * 5, Color.CYAN)
