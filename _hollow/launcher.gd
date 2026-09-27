extends Control

const SAVES_DIR = "user://_hollow_saves"
const LAST_PLAYED_FILE = "user://_last_played.txt"
const LOG_PATH = "user://debug_log.txt"
# Added debug_log.txt to SYSTEM_FILES so it doesn't get moved by your save manager!
const SYSTEM_FILES = ["_hollow_saves", "_last_played.txt", "debug_log.txt"] 

func log_msg(message: String) -> void:
	print(message)
	var time_str = Time.get_time_string_from_system()
	var line = "[" + time_str + "] " + message + "\n"
	
	var file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_string(line)
		file.close()
	else:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if file:
			file.store_string(line)
			file.close()

func _ready():
	log_msg("=== Launcher Started ===")
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)
	build_ui()

func build_ui():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	add_child(vbox)
	
	var title = Label.new()
	title.text = "Godot iOS Player\nDrop .pck files here via the iOS Files app."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var dir = DirAccess.open("user://")
	if dir:
		var files = dir.get_files()
		for file_name in files:
			if file_name.get_extension() == "pck":
				var btn = Button.new()
				btn.text = "Play: " + file_name
				btn.custom_minimum_size = Vector2(200, 60)
				btn.pressed.connect(self._on_play_pressed.bind(file_name))
				vbox.add_child(btn)

func _on_play_pressed(pck_name: String):
	log_msg("--- PLAY BUTTON PRESSED ---")
	log_msg("Target PCK: " + pck_name)
	
	manage_saves(pck_name)
	
	var pck_path = "user://".path_join(pck_name)
	var success = ProjectSettings.load_resource_pack(pck_path)
	
	if success:
		log_msg("SUCCESS: PCK loaded into memory.")
		log_msg("Attempting to change scene to res://main.tscn...")
		var err = get_tree().change_scene_to_file("res://main.tscn")
		
		if err != OK:
			log_msg("ERROR: Scene change failed! Godot Error Code: " + str(err))
		else:
			log_msg("SUCCESS: Scene changed.")
	else:
		log_msg("ERROR: Failed to load PCK file at " + pck_path)

func manage_saves(next_game: String):
	var dir = DirAccess.open("user://")
	
	if FileAccess.file_exists(LAST_PLAYED_FILE):
		var last_game = FileAccess.get_file_as_string(LAST_PLAYED_FILE).strip_edges()
		if last_game != "":
			var backup_path = SAVES_DIR.path_join(last_game)
			if not DirAccess.dir_exists_absolute(backup_path):
				DirAccess.make_dir_recursive_absolute(backup_path)
			
			var current_files = dir.get_files()
			var current_dirs = dir.get_directories()
			
			for f in current_files:
				if f not in SYSTEM_FILES and f.get_extension() != "pck":
					DirAccess.rename_absolute("user://".path_join(f), backup_path.path_join(f))
			for d in current_dirs:
				if d not in SYSTEM_FILES:
					DirAccess.rename_absolute("user://".path_join(d), backup_path.path_join(d))
	
	var restore_path = SAVES_DIR.path_join(next_game)
	if DirAccess.dir_exists_absolute(restore_path):
		var r_dir = DirAccess.open(restore_path)
		var restore_files = r_dir.get_files()
		var restore_dirs = r_dir.get_directories()
		
		for f in restore_files:
			DirAccess.rename_absolute(restore_path.path_join(f), "user://".path_join(f))
		for d in restore_dirs:
			DirAccess.rename_absolute(restore_path.path_join(d), "user://".path_join(d))
			
	var save_file = FileAccess.open(LAST_PLAYED_FILE, FileAccess.WRITE)
	save_file.store_string(next_game)
