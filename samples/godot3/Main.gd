extends Node2D

var frames = 0
var loaded = 0
var position_x = 80.0
var proving = false

func _ready():
	proving = "--player-proof" in OS.get_cmdline_args()
	var file = File.new()
	if file.file_exists("user://proof.save"):
		assert(file.open("user://proof.save", File.READ) == OK)
		loaded = int(file.get_as_text())
		file.close()
	if proving:
		var event = InputEventKey.new()
		event.scancode = KEY_RIGHT
		event.pressed = true
		Input.parse_input_event(event)

func _process(delta):
	frames += 1
	if Input.is_action_pressed("ui_right"):
		position_x += 100 * delta
	if Input.is_action_pressed("ui_left"):
		position_x -= 100 * delta
	update()
	if proving and frames == 90:
		assert(position_x > 80)
		var event = InputEventKey.new()
		event.scancode = KEY_RIGHT
		event.pressed = false
		Input.parse_input_event(event)
		var file = File.new()
		assert(file.open("user://proof.save", File.WRITE) == OK)
		file.store_string(str(loaded + 1))
		file.close()
		print("PLAYER_PROOF godot3 PASS loaded=", loaded)
		get_tree().quit()

func _draw():
	draw_rect(Rect2(0, 0, 768, 432), Color(0.04, 0.08, 0.15))
	draw_circle(Vector2(position_x, 216), 32, Color(0.1, 0.8, 0.7))
	draw_line(Vector2(40, 256), Vector2(728, 256), Color(0.25, 0.4, 0.6), 3)
