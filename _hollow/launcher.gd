extends Control

# ============================================================
# HOLLOW GODOT PLAYER
# Generic Godot 4.x PCK launcher
# ============================================================

const SAVES_DIR := "user://_hollow_saves"
const LAST_PLAYED_FILE := "user://_last_played.txt"
const LOG_PATH := "user://debug_log.txt"

const SYSTEM_FILES := [
	"_hollow_saves",
	"_last_played.txt",
	"debug_log.txt"
]

const AUTOLOAD_SEARCH_PATHS := [
	"res://scripts/autoload",
	"res://autoload",
	"res://scripts/singletons",
	"res://singletons",
	"res://scripts/globals",
	"res://scripts",
	"res://"
]

const AUTOLOAD_PRIORITY := [
	"GameData",
	"Global",
	"Globals",
	"GameState",
	"RunState",
	"MetaState",
	"PlayerData",
	"SaveData",
	"Settings",
	"DialogueManager",
	"DialogManager",
	"MusicManager",
	"AudioManager",
	"SoundManager",
	"Sfx",
	"SaveManager"
]

var launch_in_progress := false
var game_buttons: Array[Button] = []
var loaded_game_autoloads: Array[Node] = []

func log_msg(message: String) -> void:
	print(message)
	var time_str := Time.get_time_string_from_system()
	var line := "[" + time_str + "] " + message + "\n"
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_string(line)
		file.close()
	else:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if file:
			file.store_string(line)
			file.close()

func _ready() -> void:
	log_msg("\n========================================")
	log_msg("=== Hollow Player Started ===")
	log_msg("========================================")

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	build_ui()

func build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = "Hollow Godot Player\nSelect a .pck game."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var dir := DirAccess.open("user://")
	if dir:
		var files := dir.get_files()
		files.sort()
		for file_name in files:
			if file_name.get_extension().to_lower() != "pck":
				continue
			var btn := Button.new()
			btn.text = "Play: " + file_name
			btn.custom_minimum_size = Vector2(320, 60)
			btn.pressed.connect(_on_play_pressed.bind(file_name))
			vbox.add_child(btn)
			game_buttons.append(btn)

	if game_buttons.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No .pck files found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_label)

func _on_play_pressed(pck_name: String) -> void:
	if launch_in_progress:
		return
	launch_in_progress = true

	for button in game_buttons:
		if is_instance_valid(button):
			button.disabled = true

	log_msg("\n========================================")
	log_msg("--- PLAY BUTTON PRESSED ---")
	log_msg("Target PCK: " + pck_name)

	var pck_path := "user://".path_join(pck_name)

	if not FileAccess.file_exists(pck_path):
		log_msg("ERROR: PCK does not exist: " + pck_path)
		reset_launcher()
		return

	log_msg("PCK file exists.")
	manage_saves(pck_name)

	log_msg("Loading PCK...")
	var loaded := ProjectSettings.load_resource_pack(pck_path, true)

	if not loaded:
		log_msg("ERROR: Failed to load PCK.")
		reset_launcher()
		return

	log_msg("SUCCESS: PCK loaded into memory.")

	var game_settings := get_pck_settings()

	if not game_settings.is_empty():
		log_msg("Game configuration extracted from PCK.")
		apply_basic_game_settings(game_settings)
	else:
		log_msg("No configuration found inside PCK. Fallbacks will apply.")

	var autoloads_ok := setup_game_autoloads(game_settings)
	if not autoloads_ok:
		log_msg("WARNING: No game autoloads were loaded.")
	else:
		log_msg("Game autoload setup completed.")

	await get_tree().process_frame

	var main_scene := find_game_main_scene(game_settings)

	if main_scene == "":
		log_msg("ERROR: Could not find a playable main scene.")
		reset_launcher()
		return

	log_msg("Detected main scene: " + main_scene)

	if not ResourceLoader.exists(main_scene):
		log_msg("ERROR: ResourceLoader cannot find: " + main_scene)
		reset_launcher()
		return

	var packed_scene = ResourceLoader.load(main_scene)
	if packed_scene == null or not packed_scene is PackedScene:
		log_msg("ERROR: Main scene could not be loaded or is not a PackedScene.")
		reset_launcher()
		return

	var scene := packed_scene as PackedScene
	if not scene.can_instantiate():
		log_msg("ERROR: Main scene cannot be instantiated.")
		reset_launcher()
		return

	log_msg("SUCCESS: Main scene loaded. Starting game...")
	var error := get_tree().change_scene_to_packed(scene)

	if error != OK:
		log_msg("ERROR: Scene change failed. Error code: " + str(error))
		reset_launcher()
		return

	log_msg("SUCCESS: Game started.")
	log_msg("========================================\n")

func get_pck_settings() -> Dictionary:
	var settings := {}

	if FileAccess.file_exists("res://project.godot"):
		var config := ConfigFile.new()
		if config.load("res://project.godot") == OK:
			for section in config.get_sections():
				for key in config.get_section_keys(section):
					settings[section + "/" + key] = config.get_value(section, key)
			return settings

	if FileAccess.file_exists("res://project.binary"):
		var file := FileAccess.open("res://project.binary", FileAccess.READ)
		if file:
			var magic := file.get_32()
			if magic == 0x43464745 or magic == 0x47464345:
				var count := file.get_32()
				if count > 0 and count < 65536:
					for i in range(count):
						if file.get_position() >= file.get_length():
							break
						var key = file.get_var()
						var val = file.get_var()
						if key != null and val != null:
							settings[String(key)] = val
			file.close()

	return settings

func apply_basic_game_settings(settings: Dictionary) -> void:
	var width = settings.get("display/window/size/viewport_width", null)
	var height = settings.get("display/window/size/viewport_height", null)

	if width is int and height is int:
		if width > 0 and height > 0:
			get_window().content_scale_size = Vector2i(width, height)
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			log_msg("Applied game content size: " + str(width) + "x" + str(height))

func setup_game_autoloads(settings: Dictionary) -> bool:
	clear_previous_game_autoloads()

	var found_entries: Array[Dictionary] = []

	for key in settings.keys():
		if key.begins_with("autoload/"):
			var autoload_name = key.trim_prefix("autoload/")
			var autoload_value = settings[key]

			if not autoload_value is String:
				continue

			var path := String(autoload_value)
			var is_singleton := path.begins_with("*")

			if is_singleton:
				path = path.substr(1)

			if path == "":
				continue

			found_entries.append({
				"name": autoload_name,
				"path": path,
				"is_singleton": is_singleton
			})

	if not found_entries.is_empty():
		log_msg("Using exact autoload configuration from PCK.")
		for entry in found_entries:
			load_autoload_entry(entry["name"], entry["path"], entry["is_singleton"])
		return not loaded_game_autoloads.is_empty()

	log_msg("Searching for autoload resources via fallback discovery...")
	var candidates: Array[Dictionary] = []

	for folder in AUTOLOAD_SEARCH_PATHS:
		if not ResourceLoader.exists(folder):
			continue
		collect_autoload_resources(folder, candidates)

	if candidates.is_empty():
		return false

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_priority := autoload_priority(String(a["name"]))
			var b_priority := autoload_priority(String(b["name"]))
			if a_priority != b_priority:
				return a_priority < b_priority
			return String(a["name"]).to_lower() < String(b["name"]).to_lower()
	)

	for candidate in candidates:
		load_autoload_entry(candidate["name"], candidate["path"], true)

	return not loaded_game_autoloads.is_empty()

func collect_autoload_resources(folder_path: String, results: Array[Dictionary]) -> void:
	var entries := ResourceLoader.list_directory(folder_path)
	for entry in entries:
		if entry.ends_with("/"):
			var child_name := entry.trim_suffix("/")
			if child_name == "_hollow" or child_name == "scenes" or child_name == "ui":
				continue
			collect_autoload_resources(folder_path.path_join(child_name), results)
			continue

		var lower := entry.to_lower()
		var valid_script := lower.ends_with(".gd") or lower.ends_with(".gdc") or lower.ends_with(".gd.remap")
		var valid_scene := lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap")

		if not (valid_script or valid_scene):
			continue

		var clean_name := entry.get_file()
		if clean_name.ends_with(".remap"):
			clean_name = clean_name.trim_suffix(".remap")
		var base_name := clean_name.get_basename()

		if base_name == "" or base_name == "launcher":
			continue

		var path := folder_path.path_join(entry)
		if path.ends_with(".remap"):
			path = path.trim_suffix(".remap")

		var already_exists := false
		for r in results:
			if r["name"] == base_name:
				already_exists = true
				break

		if not already_exists:
			results.append({
				"name": base_name,
				"path": path
			})

func autoload_priority(name: String) -> int:
	var lower := name.to_lower()
	for i in range(AUTOLOAD_PRIORITY.size()):
		if lower == String(AUTOLOAD_PRIORITY[i]).to_lower():
			return i
	return 1000

func load_autoload_entry(autoload_name: String, path: String, is_singleton: bool) -> void:
	if not is_singleton:
		return

	if get_tree().root.has_node(autoload_name):
		log_msg("Autoload already exists: " + autoload_name)
		return

	var clean_path := path
	if clean_path.ends_with(".remap"):
		clean_path = clean_path.trim_suffix(".remap")

	log_msg("Loading autoload: " + autoload_name + " -> " + clean_path)

	if ResourceLoader.exists(clean_path):
		var res = ResourceLoader.load(clean_path)
		if res is Script:
			var instance = res.new()
			if instance is Node:
				instance.name = autoload_name
				get_tree().root.add_child(instance)
				loaded_game_autoloads.append(instance)
				log_msg("  Autoload script started: " + autoload_name)
				return
		elif res is PackedScene:
			var node := res.instantiate()
			if node != null:
				node.name = autoload_name
				get_tree().root.add_child(node)
				loaded_game_autoloads.append(node)
				log_msg("  Autoload scene started: " + autoload_name)
				return

	log_msg("WARNING: Failed to load autoload: " + clean_path)

func clear_previous_game_autoloads() -> void:
	for node in loaded_game_autoloads:
		if is_instance_valid(node):
			node.queue_free()
	loaded_game_autoloads.clear()

func find_game_main_scene(settings: Dictionary) -> String:
	if settings.has("application/run/main_scene"):
		var configured_scene = settings["application/run/main_scene"]
		if configured_scene is String and configured_scene != "":
			if ResourceLoader.exists(configured_scene):
				log_msg("Using main_scene from PCK configuration: " + configured_scene)
				return configured_scene

	log_msg("Fallback: Searching exported PCK for scenes...")
	var scenes: Array[String] = []
	collect_scene_resources("res://", scenes)

	if scenes.is_empty():
		return ""

	for scene_path in scenes:
		var lower_name := scene_path.get_file().to_lower()
		if lower_name == "main.tscn":
			return scene_path

	for scene_path in scenes:
		var lower_name := scene_path.get_file().to_lower()
		if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):
			return scene_path

	return scenes[0]

func collect_scene_resources(folder_path: String, results: Array[String]) -> void:
	var entries := ResourceLoader.list_directory(folder_path)
	for entry in entries:
		if entry.ends_with("/"):
			var child_name := entry.trim_suffix("/")
			if child_name == "_hollow":
				continue
			collect_scene_resources(folder_path.path_join(child_name), results)
			continue

		var lower := entry.to_lower()
		if lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap"):
			var path := folder_path.path_join(entry)
			if path.ends_with(".remap"):
				path = path.trim_suffix(".remap")
			if not "/_hollow/" in path.to_lower() and path != "res://launcher.tscn":
				results.append(path)

func manage_saves(next_game: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return

	if FileAccess.file_exists(LAST_PLAYED_FILE):
		var last_game := FileAccess.get_file_as_string(LAST_PLAYED_FILE).strip_edges()
		if last_game != "":
			var backup_path := SAVES_DIR.path_join(last_game)
			if not DirAccess.dir_exists_absolute(backup_path):
				DirAccess.make_dir_recursive_absolute(backup_path)

			for file_name in dir.get_files():
				if file_name in SYSTEM_FILES or file_name.get_extension().to_lower() == "pck":
					continue
				var source := "user://".path_join(file_name)
				var destination := backup_path.path_join(file_name)
				DirAccess.rename_absolute(source, destination)

			for directory_name in dir.get_directories():
				if directory_name in SYSTEM_FILES:
					continue
				var source := "user://".path_join(directory_name)
				var destination := backup_path.path_join(directory_name)
				DirAccess.rename_absolute(source, destination)

	var restore_path := SAVES_DIR.path_join(next_game)
	if DirAccess.dir_exists_absolute(restore_path):
		var restore_dir := DirAccess.open(restore_path)
		if restore_dir:
			for file_name in restore_dir.get_files():
				DirAccess.rename_absolute(restore_path.path_join(file_name), "user://".path_join(file_name))
			for directory_name in restore_dir.get_directories():
				DirAccess.rename_absolute(restore_path.path_join(directory_name), "user://".path_join(directory_name))

	var save_file := FileAccess.open(LAST_PLAYED_FILE, FileAccess.WRITE)
	if save_file:
		save_file.store_string(next_game)
		save_file.close()

func reset_launcher() -> void:
	launch_in_progress = false
	for button in game_buttons:
		if is_instance_valid(button):
			button.disabled = false
