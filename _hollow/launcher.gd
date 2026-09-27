extends Control

const LOG_PATH = "user://debug_log.txt"
var debug_label: Label

func _ready() -> void:
	_setup_debug_label()
	log_msg("=== Launcher Started ===")

func _setup_debug_label() -> void:
	if has_node("DebugLabel"):
		debug_label = $DebugLabel
	else:
		debug_label = Label.new()
		debug_label.name = "DebugLabel"
		debug_label.position = Vector2(30, 80)
		debug_label.add_theme_color_override("font_color", Color.RED)
		debug_label.add_theme_font_size_override("font_size", 22)
		add_child(debug_label)

func log_msg(message: String) -> void:
	print(message)
	var time_str = Time.get_time_string_from_system()
	var line = "[" + time_str + "] " + message
	
	# 1. Print directly on screen
	if debug_label:
		debug_label.text += line + "\n"
		
	# 2. Write to debug_log.txt in Files App
	var file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_string(line + "\n")
		file.close()
	else:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if file:
			file.store_string(line + "\n")
			file.close()

func _on_play_button_pressed() -> void:
	log_msg("Play button pressed.")
	
	# Change "user://game.pck" if your PCK file has a different name
	var pck_path = "user://game.pck" 
	
	if not FileAccess.file_exists(pck_path):
		log_msg("ERROR: PCK file not found at: " + pck_path)
		return
		
	log_msg("Attempting to mount PCK: " + pck_path)
	var pck_loaded = ProjectSettings.load_resource_pack(pck_path)
	
	if not pck_loaded:
		log_msg("ERROR: ProjectSettings failed to mount PCK!")
		return
		
	log_msg("PCK mounted. Attempting to change scene...")
	
	# Change "res://main.tscn" to the exact main scene path in your game's PCK
	var target_scene = "res://main.tscn" 
	
	var err = get_tree().change_scene_to_file(target_scene)
	if err != OK:
		log_msg("ERROR: Could not change scene. Godot Error Code: " + str(err))
	else:
		log_msg("Scene change command executed successfully.")
