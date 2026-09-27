extends Control

# ============================================================
# HOLLOW GODOT PLAYER
# Generic Godot 4.x PCK launcher
# ============================================================

const SAVES_DIR := "user://_hollow_saves"
const LAST_PLAYED_FILE := "user://_last_played.txt"

const SYSTEM_FILES := [
	"_hollow_saves",
	"_last_played.txt"
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
	"GameData", "Global", "Globals", "GameState", "RunState",
	"MetaState", "PlayerData", "SaveData", "Settings",
	"DialogueManager", "DialogManager", "MusicManager",
	"AudioManager", "SoundManager", "Sfx", "SaveManager"
]

var log_file_path := ""
var launch_in_progress := false
var game_buttons: Array[Button] = []
var loaded_game_autoloads: Array[Node] = []

# ============================================================
# LOGGING
# ============================================================

func log_msg(message: String) -> void:
	print(message)
	if log_file_path == "":
		return

	var time_str := Time.get_time_string_from_system()
	var line := "[" + time_str + "] " + message + "\n"

	var file := FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_string(line)
		file.close()
	else:
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
		if file:
			file.store_string(line)
			file.close()

# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	var datetime_string := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	log_file_path = "user://hollow_run_" + datetime_string + ".log"

	log_msg("==================================================")
	log_msg("HOLLOW GODOT PLAYER INITIALIZED")
	log_msg("Engine Version: " + Engine.get_version_info().string)
	log_msg("Active Log File: " + log_file_path)
	log_msg("==================================================")

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)
		log_msg("Created missing saves directory at: " + SAVES_DIR)

	build_ui()

# ============================================================
# LAUNCHER UI
# ============================================================

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

# ============================================================
# PLAY GAME SEQUENCE
# ============================================================

func _on_play_pressed(pck_name: String) -> void:
	if launch_in_progress:
		return
	launch_in_progress = true

	for button in game_buttons:
		if is_instance_valid(button):
			button.disabled = true

	log_msg("\n==================================================")
	log_msg("INITIATING GAME LAUNCH SEQUENCE")
	log_msg("Target File: " + pck_name)
	log_msg("==================================================")

	var pck_path := "user://".path_join(pck_name)

	if not FileAccess.file_exists(pck_path):
		log_msg("FATAL ERROR: Target PCK does not exist at path: " + pck_path)
		reset_launcher()
		return

	# STEP 1: Manage Save Data Isolation
	log_msg("\n[STEP 1] ISOLATING SAVE DATA")
	manage_saves(pck_name)

	# STEP 2: Load the PCK File
	log_msg("\n[STEP 2] MOUNTING PCK FILE")
	log_msg("Attempting to overlay " + pck_name + " onto the virtual res:// filesystem...")
	var loaded := ProjectSettings.load_resource_pack(pck_path, true)

	if not loaded:
		log_msg("FATAL ERROR: Engine failed to load resource pack. The file may be corrupt or for an incompatible Godot version.")
		reset_launcher()
		return
	log_msg("SUCCESS: PCK successfully mounted to res://.")

	# STEP 3: Extract Binary Project Settings
	log_msg("\n[STEP 3] EXTRACTING COMPILED PROJECT SETTINGS")
	var game_config := read_game_project_config()

	if not game_config.is_empty():
		log_msg("SUCCESS: Configuration map generated successfully.")
	else:
		log_msg("WARNING: No valid configuration map could be extracted. The game may operate unpredictably.")

	# STEP 4: Apply Engine Overrides and Input Maps
	log_msg("\n[STEP 4] INJECTING CONFIGURATION & REBUILDING INPUT MAPS")
	apply_engine_overrides(game_config)

	# STEP 5: Initialize Autoload Singletons
	log_msg("\n[STEP 5] INSTANTIATING AUTOLOAD MANAGERS")
	var autoloads_ok := setup_game_autoloads(game_config)
	if not autoloads_ok:
		log_msg("WARNING: No autoloads initialized. If this game requires background managers, it will likely crash or hang on a debug screen.")

	# Wait for singleton _ready calls to finish
	log_msg("Awaiting next engine frame to allow Autoload _ready() functions to execute...")
	await get_tree().process_frame

	# STEP 6: Identify and Launch Main Scene
	log_msg("\n[STEP 6] LOCATING AND BOOTING MAIN SCENE")
	var main_scene := find_game_main_scene(game_config)

	if main_scene == "":
		log_msg("FATAL ERROR: No eligible main scene discovered in configuration or PCK root.")
		reset_launcher()
		return

	log_msg("Target Main Scene identified as: " + main_scene)

	if not ResourceLoader.exists(main_scene):
		log_msg("FATAL ERROR: Engine reports main scene does not exist in the mounted res:// filesystem.")
		reset_launcher()
		return

	log_msg("Loading main scene resource into memory...")
	var packed_scene = ResourceLoader.load(main_scene)

	if packed_scene == null or not packed_scene is PackedScene:
		log_msg("FATAL ERROR: The resource at " + main_scene + " is not a valid PackedScene.")
		reset_launcher()
		return

	if not packed_scene.can_instantiate():
		log_msg("FATAL ERROR: The PackedScene cannot be instantiated. It may have missing dependencies.")
		reset_launcher()
		return

	log_msg("Executing active scene replacement...")
	var error := get_tree().change_scene_to_packed(packed_scene)

	if error != OK:
		log_msg("FATAL ERROR: Engine failed to swap the scene tree. Error Code: " + str(error))
		reset_launcher()
		return

	log_msg("==================================================")
	log_msg("SUCCESS: GAME BOOT SEQUENCE COMPLETE")
	log_msg("Control successfully transferred to " + pck_name)
	log_msg("==================================================")

# ============================================================
# CONFIGURATION PARSING
# ============================================================

func read_game_project_config() -> Dictionary:
	var settings := {}

	# Fallback for text-based project files
	if ResourceLoader.exists("res://project.godot"):
		log_msg("Text-based project.godot found. Parsing INI format...")
		var config := ConfigFile.new()
		if config.load("res://project.godot") == OK:
			for section in config.get_sections():
				for key in config.get_section_keys(section):
					settings[section + "/" + key] = config.get_value(section, key)
			return settings

	if FileAccess.file_exists("res://project.binary"):
		log_msg("Compiled project.binary found. Executing sequential byte deserialization...")
		var file := FileAccess.open("res://project.binary", FileAccess.READ)

		if file:
			var magic := file.get_32()
			if magic == 0x43464745 or magic == 0x47464345:
				log_msg("Valid ECFG magic header verified.")
				var _version := file.get_32()
				var count := file.get_32()
				log_msg("Declared settings block count: " + str(count))

				var parsed_keys := 0
				if count > 0 and count < 65536:
					for i in range(count):
						if file.get_position() >= file.get_length():
							log_msg("Parsing halted: Reached EOF unexpectedly at index " + str(i))
							break

						var key = file.get_var()
						var val = file.get_var()

						if key != null and key is String and val != null:
							if typeof(val) == TYPE_DICTIONARY and val.has("value"):
								settings[key] = val["value"]
							else:
								settings[key] = val
							parsed_keys += 1
				log_msg("Deserialization complete. Parsed " + str(parsed_keys) + " valid setting pairs.")
			else:
				log_msg("Parsing failed: Invalid magic header in project.binary.")
			file.close()
	else:
		log_msg("No project.binary file detected in the exported pack.")

	return settings

# ============================================================
# INJECT SETTINGS & INPUTS
# ============================================================

func apply_engine_overrides(config: Dictionary) -> void:
	var total_applied := 0
	for key in config.keys():
		ProjectSettings.set_setting(key, config[key])
		total_applied += 1
	
	log_msg("Injected " + str(total_applied) + " variables into the global ProjectSettings object.")

	# UI Scaling Setup
	var width = config.get("display/window/size/viewport_width", null)
	var height = config.get("display/window/size/viewport_height", null)

	if width is int and height is int and width > 0 and height > 0:
		get_window().content_scale_size = Vector2i(width, height)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		log_msg("Viewport rendering bounds dynamically adjusted to: " + str(width) + "x" + str(height))
	else:
		log_msg("No valid viewport dimensions found. Inheriting launcher default scaling.")

	# InputMap Rebuild
	log_msg("Rebuilding engine InputMap from updated ProjectSettings...")
	InputMap.load_from_project_settings()
	log_msg("InputMap reconstruction complete. Game-specific keybinds and virtual inputs are now active.")

# ============================================================
# AUTOLOAD INJECTION
# ============================================================

func setup_game_autoloads(config: Dictionary) -> bool:
	clear_previous_game_autoloads()

	var found_entries: Array[Dictionary] = []

	# Method 1: Extract strictly from project.binary
	for key in config.keys():
		if key.begins_with("autoload/"):
			var autoload_name = key.trim_prefix("autoload/")
			var autoload_value = config[key]

			if not autoload_value is String:
				continue

			var path := str(autoload_value)
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
		log_msg("Explicit Autoload mappings found in configuration.")
		for entry in found_entries:
			load_autoload_entry(entry["name"], entry["path"], entry["is_singleton"])
		return not loaded_game_autoloads.is_empty()

	# Method 2: Manual Directory Crawl
	log_msg("No explicit mappings found. Falling back to heuristic directory search...")
	var candidates: Array[Dictionary] = []

	for folder in AUTOLOAD_SEARCH_PATHS:
		if not ResourceLoader.exists(folder):
			continue
		collect_autoload_resources(folder, candidates)

	if candidates.is_empty():
		return false

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_name := str(a["name"])
			var b_name := str(b["name"])
			var a_priority := autoload_priority(a_name)
			var b_priority := autoload_priority(b_name)
			if a_priority != b_priority:
				return a_priority < b_priority
			return a_name.to_lower() < b_name.to_lower()
	)

	for candidate in candidates:
		load_autoload_entry(candidate["name"], candidate["path"], true)

	return not loaded_game_autoloads.is_empty()

func collect_autoload_resources(folder_path: String, results: Array[Dictionary]) -> void:
	var entries := ResourceLoader.list_directory(folder_path)
	for entry in entries:
		if entry.ends_with("/"):
			var child_name := entry.trim_suffix("/")
			if child_name == "scenes" or child_name == "ui":
				continue
			collect_autoload_resources(folder_path.path_join(child_name), results)
			continue

		var lower := entry.to_lower()
		var valid_script := lower.ends_with(".gd") or lower.ends_with(".gdc") or lower.ends_with(".gd.remap")
		var valid_scene := lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap")

		if not (valid_script or valid_scene):
			continue

		var full_path := folder_path.path_join(entry)
		if full_path.ends_with(".remap"):
			full_path = full_path.trim_suffix(".remap")

		var file_name := entry.get_file()
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		var base_name := file_name.get_basename()

		if base_name == "" or base_name == "launcher":
			continue

		var already_exists := false
		for r in results:
			if r["name"] == base_name:
				already_exists = true
				break

		if not already_exists:
			results.append({
				"name": base_name,
				"path": full_path
			})

func autoload_priority(name: String) -> int:
	var lower := name.to_lower()
	for i in range(AUTOLOAD_PRIORITY.size()):
		if lower == str(AUTOLOAD_PRIORITY[i]).to_lower():
			return i
	return 1000

func load_autoload_entry(autoload_name: String, path: String, is_singleton: bool) -> void:
	if not is_singleton:
		return

	if get_tree().root.has_node(autoload_name):
		return

	var clean_path := path
	if clean_path.ends_with(".remap"):
		clean_path = clean_path.trim_suffix(".remap")

	if not ResourceLoader.exists(clean_path):
		log_msg("FAILED to load singleton '" + autoload_name + "'. Target path missing: " + clean_path)
		return

	var ext := clean_path.get_extension().to_lower()

	if ext == "gd" or ext == "gdc":
		var script = ResourceLoader.load(clean_path)
		if script is Script:
			var instance = script.new()
			if instance != null and instance is Node:
				instance.name = autoload_name
				get_tree().root.add_child(instance)
				loaded_game_autoloads.append(instance)
				log_msg("-> Attached GDScript Singleton: " + autoload_name + " (" + clean_path + ")")
			else:
				log_msg("FAILED: Singleton script " + autoload_name + " does not inherit from Node.")
		return

	if ext == "tscn" or ext == "scn":
		var resource = ResourceLoader.load(clean_path)
		if resource is PackedScene:
			var node := resource.instantiate()
			if node != null:
				node.name = autoload_name
				get_tree().root.add_child(node)
				loaded_game_autoloads.append(node)
				log_msg("-> Attached PackedScene Singleton: " + autoload_name + " (" + clean_path + ")")
			else:
				log_msg("FAILED: Singleton scene " + autoload_name + " could not be instantiated.")
		return

func clear_previous_game_autoloads() -> void:
	for node in loaded_game_autoloads:
		if is_instance_valid(node):
			node.queue_free()
	loaded_game_autoloads.clear()

# ============================================================
# MAIN SCENE DISCOVERY
# ============================================================

func find_game_main_scene(config: Dictionary) -> String:
	# Method 1: Config
	if config.has("application/run/main_scene"):
		var configured_scene = config["application/run/main_scene"]
		if configured_scene is String and configured_scene != "":
			if ResourceLoader.exists(configured_scene):
				log_msg("Main scene located via project settings map.")
				return configured_scene
			else:
				log_msg("WARNING: Configured main scene does not exist in res://. Falling back to scan.")

	# Method 2: Scan
	log_msg("Executing recursive scan of res:// for entry points...")
	var scenes: Array[String] = []
	collect_scene_resources("res://", scenes)
	log_msg("Scan complete. Located " + str(scenes.size()) + " total scene files.")

	if scenes.is_empty():
		return ""

	var targets := [
		"main.tscn", "mainscene.tscn", "start.tscn", "game.tscn",
		"main.tscn.remap", "mainscene.tscn.remap", "start.tscn.remap", "game.tscn.remap"
	]

	for target in targets:
		for scene_path in scenes:
			if scene_path.get_file().to_lower() == target:
				log_msg("Main scene located via naming heuristics priority match.")
				return scene_path

	for scene_path in scenes:
		var relative := scene_path.trim_prefix("res://")
		if "/" not in relative:
			var lower_name := scene_path.get_file().to_lower()
			if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):
				log_msg("Main scene located via root directory default selection.")
				return scene_path

	scenes.sort()
	for scene_path in scenes:
		var lower_name := scene_path.get_file().to_lower()
		if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):
			log_msg("Main scene located via alphabetical fallback.")
			return scene_path

	return scenes[0]

func collect_scene_resources(folder_path: String, results: Array[String]) -> void:
	var entries := ResourceLoader.list_directory(folder_path)
	for entry in entries:
		if entry.ends_with("/"):
			var child_name := entry.trim_suffix("/")
			collect_scene_resources(folder_path.path_join(child_name), results)
			continue

		var lower := entry.to_lower()
		if lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap"):
			var path := folder_path.path_join(entry)
			if path.ends_with(".remap"):
				path = path.trim_suffix(".remap")
			if not path.to_lower().ends_with("launcher.tscn"):
				results.append(path)

# ============================================================
# SAVE MANAGEMENT
# ============================================================

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

			var current_files := dir.get_files()
			var current_dirs := dir.get_directories()
			var moved_count := 0

			for file_name in current_files:
				if file_name in SYSTEM_FILES or file_name.get_extension().to_lower() == "pck":
					continue
				if file_name.begins_with("hollow_run_") and file_name.ends_with(".log"):
					continue
				var source := "user://".path_join(file_name)
				var destination := backup_path.path_join(file_name)
				if DirAccess.rename_absolute(source, destination) == OK:
					moved_count += 1

			for directory_name in current_dirs:
				if directory_name in SYSTEM_FILES:
					continue
				var source := "user://".path_join(directory_name)
				var destination := backup_path.path_join(directory_name)
				if DirAccess.rename_absolute(source, destination) == OK:
					moved_count += 1
			
			log_msg("Archived " + str(moved_count) + " files/folders from previous game: " + last_game)

	var restore_path := SAVES_DIR.path_join(next_game)
	if DirAccess.dir_exists_absolute(restore_path):
		var restore_dir := DirAccess.open(restore_path)
		if restore_dir:
			var restored_count := 0
			for file_name in restore_dir.get_files():
				if DirAccess.rename_absolute(restore_path.path_join(file_name), "user://".path_join(file_name)) == OK:
					restored_count += 1
			for directory_name in restore_dir.get_directories():
				if DirAccess.rename_absolute(restore_path.path_join(directory_name), "user://".path_join(directory_name)) == OK:
					restored_count += 1
			
			log_msg("Restored " + str(restored_count) + " localized save files/folders for target game.")

	var save_file := FileAccess.open(LAST_PLAYED_FILE, FileAccess.WRITE)
	if save_file:
		save_file.store_string(next_game)
		save_file.close()

# ============================================================
# RESET LAUNCHER
# ============================================================

func reset_launcher() -> void:
	launch_in_progress = false
	for button in game_buttons:
		if is_instance_valid(button):
			button.disabled = false
