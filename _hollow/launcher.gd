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

# Used only when the PCK does not contain project.godot.
# These are common foundational manager names and also preserve
# the order used by I Can Smell You from Here.
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


# ============================================================
# LOGGING
# ============================================================

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


# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	log_msg("")
	log_msg("========================================")
	log_msg("=== Hollow Player Started ===")
	log_msg("========================================")

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)

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

			btn.pressed.connect(
				_on_play_pressed.bind(file_name)
			)

			vbox.add_child(btn)

			game_buttons.append(btn)

	if game_buttons.is_empty():

		var empty_label := Label.new()

		empty_label.text = "No .pck files found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		vbox.add_child(empty_label)


# ============================================================
# PLAY GAME
# ============================================================

func _on_play_pressed(pck_name: String) -> void:

	if launch_in_progress:
		return

	launch_in_progress = true

	for button in game_buttons:

		if is_instance_valid(button):
			button.disabled = true


	log_msg("")
	log_msg("========================================")
	log_msg("--- PLAY BUTTON PRESSED ---")
	log_msg("Target PCK: " + pck_name)


	var pck_path := "user://".path_join(pck_name)


	# --------------------------------------------------------
	# CHECK FILE
	# --------------------------------------------------------

	if not FileAccess.file_exists(pck_path):

		log_msg("ERROR: PCK does not exist.")
		log_msg(pck_path)

		reset_launcher()
		return


	log_msg("PCK file exists.")


	# --------------------------------------------------------
	# SAVE MANAGEMENT
	# --------------------------------------------------------

	manage_saves(pck_name)


	# --------------------------------------------------------
	# LOAD PCK
	# --------------------------------------------------------

	log_msg("Loading PCK...")

	var loaded := ProjectSettings.load_resource_pack(
		pck_path,
		true
	)

	if not loaded:

		log_msg("ERROR: Failed to load PCK.")
		log_msg("Path: " + pck_path)

		reset_launcher()
		return


	log_msg("SUCCESS: PCK loaded into memory.")


	# --------------------------------------------------------
	# READ GAME CONFIGURATION
	# --------------------------------------------------------

	var game_config := read_game_project_config()

	if not game_config.is_empty():

		log_msg("Game project configuration found inside PCK.")

		apply_basic_game_settings(game_config)

	else:

		log_msg(
			"No project configuration found inside PCK."
		)

		log_msg(
			"Using automatic discovery."
		)


	# --------------------------------------------------------
	# CREATE GAME AUTOLOADS
	# --------------------------------------------------------

	var autoloads_ok := setup_game_autoloads(
		game_config
	)

	if not autoloads_ok:

		log_msg(
			"WARNING: No game autoloads were discovered."
		)

	else:

		log_msg(
			"Game autoload setup completed."
		)


	# --------------------------------------------------------
	# WAIT ONE FRAME
	#
	# This gives newly-created autoload nodes time to enter
	# the scene tree and run their _ready() methods.
	# --------------------------------------------------------

	await get_tree().process_frame


	# --------------------------------------------------------
	# FIND MAIN SCENE
	# --------------------------------------------------------

	var main_scene := find_game_main_scene(
		game_config
	)

	if main_scene == "":

		log_msg(
			"ERROR: Could not find a playable main scene."
		)

		reset_launcher()
		return


	log_msg(
		"Detected main scene: "
		+ main_scene
	)


	# --------------------------------------------------------
	# VERIFY SCENE
	# --------------------------------------------------------

	if not ResourceLoader.exists(main_scene):

		log_msg(
			"ERROR: ResourceLoader cannot find:"
		)

		log_msg(main_scene)

		reset_launcher()
		return


	var packed_scene = ResourceLoader.load(main_scene)


	if packed_scene == null:

		log_msg(
			"ERROR: Main scene could not be loaded:"
		)

		log_msg(main_scene)

		reset_launcher()
		return


	if not packed_scene is PackedScene:

		log_msg(
			"ERROR: Main scene is not a PackedScene:"
		)

		log_msg(main_scene)

		reset_launcher()
		return


	var scene := packed_scene as PackedScene


	if not scene.can_instantiate():

		log_msg(
			"ERROR: Main scene cannot be instantiated:"
		)

		log_msg(main_scene)

		reset_launcher()
		return


	log_msg(
		"SUCCESS: Main scene loaded."
	)

	log_msg(
		"Starting game..."
	)


	# --------------------------------------------------------
	# START GAME
	# --------------------------------------------------------

	var error := get_tree().change_scene_to_packed(scene)


	if error != OK:

		log_msg(
			"ERROR: Scene change failed."
		)

		log_msg(
			"Error code: " + str(error)
		)

		reset_launcher()
		return


	log_msg(
		"SUCCESS: Game started."
	)

	log_msg("========================================")


# ============================================================
# READ CONFIGURATION FROM PCK
# ============================================================

func read_game_project_config() -> Dictionary:

	var settings := {}

	if ResourceLoader.exists("res://project.godot"):

		var config := ConfigFile.new()

		var error := config.load(
			"res://project.godot"
		)

		if error == OK:
			for section in config.get_sections():
				for key in config.get_section_keys(section):
					settings[section + "/" + key] = config.get_value(section, key)

			return settings


	if FileAccess.file_exists("res://project.binary"):

		var file := FileAccess.open("res://project.binary", FileAccess.READ)

		if file:
			var magic := file.get_32()

			if magic == 0x43464745 or magic == 0x47464345:
				var _version := file.get_32()
				var count := file.get_32()

				if count > 0 and count < 65536:
					for i in range(count):

						if file.get_position() >= file.get_length():
							break

						var key = file.get_var()
						var val = file.get_var()

						if key != null and val != null:
							if typeof(val) == TYPE_DICTIONARY and val.has("value"):
								settings[str(key)] = val["value"]
							else:
								settings[str(key)] = val

			file.close()


	for key in settings.keys():
		ProjectSettings.set_setting(key, settings[key])

	return settings


# ============================================================
# APPLY BASIC PROJECT SETTINGS
# ============================================================

func apply_basic_game_settings(
	config: Dictionary
) -> void:

	var width = config.get("display/window/size/viewport_width", null)
	var height = config.get("display/window/size/viewport_height", null)

	if width is int and height is int:

		if width > 0 and height > 0:

			get_window().content_scale_size = Vector2i(
				width,
				height
			)

			get_window().content_scale_mode = (
				Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			)

			log_msg(
				"Applied game content size: "
				+ str(width)
				+ "x"
				+ str(height)
			)


# ============================================================
# AUTOLOAD SETUP
# ============================================================

func setup_game_autoloads(
	config: Dictionary
) -> bool:

	clear_previous_game_autoloads()


	var found_entries: Array[Dictionary] = []


	# --------------------------------------------------------
	# METHOD 1:
	# Exact autoload list from the game's configuration
	# --------------------------------------------------------

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

		log_msg(
			"Using autoload order from configuration."
		)

		for entry in found_entries:

			load_autoload_entry(
				entry["name"],
				entry["path"],
				entry["is_singleton"]
			)

		return not loaded_game_autoloads.is_empty()


	# --------------------------------------------------------
	# METHOD 2:
	# Automatic folder discovery
	# --------------------------------------------------------

	log_msg(
		"Searching for autoload scripts automatically..."
	)


	var candidates: Array[Dictionary] = []

	for folder in AUTOLOAD_SEARCH_PATHS:

		if not ResourceLoader.exists(
			folder
		):
			continue

		collect_autoload_resources(
			folder,
			candidates
		)


	if candidates.is_empty():

		log_msg(
			"No automatic autoload resources found."
		)

		return false


	# --------------------------------------------------------
	# Sort using preferred manager names first.
	# --------------------------------------------------------

	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:

			var a_name := str(a["name"])
			var b_name := str(b["name"])

			var a_priority := autoload_priority(
				a_name
			)

			var b_priority := autoload_priority(
				b_name
			)

			if a_priority != b_priority:
				return a_priority < b_priority

			return a_name.to_lower() < b_name.to_lower()
	)


	for candidate in candidates:

		load_autoload_entry(
			candidate["name"],
			candidate["path"],
			true
		)


	return not loaded_game_autoloads.is_empty()


# ============================================================
# AUTOLOAD RESOURCE DISCOVERY
# ============================================================

func collect_autoload_resources(
	folder_path: String,
	results: Array[Dictionary]
) -> void:

	var entries := ResourceLoader.list_directory(
		folder_path
	)


	for entry in entries:

		if entry.ends_with("/"):

			var child_name := entry.trim_suffix("/")

			var child_path := folder_path.path_join(
				child_name
			)

			collect_autoload_resources(
				child_path,
				results
			)

			continue


		var lower := entry.to_lower()

		var valid_script := lower.ends_with(".gd") or lower.ends_with(".gdc") or lower.ends_with(".gd.remap")
		var valid_scene := lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap")


		if not (valid_script or valid_scene):
			continue


		var full_path := folder_path.path_join(
			entry
		)

		if full_path.ends_with(".remap"):
			full_path = full_path.trim_suffix(".remap")


		var file_name := entry.get_file()

		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")

		var base_name := file_name.get_basename()


		if base_name == "":
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


# ============================================================
# AUTOLOAD PRIORITY
# ============================================================

func autoload_priority(name: String) -> int:

	var lower := name.to_lower()

	for i in range(
		AUTOLOAD_PRIORITY.size()
	):

		if lower == (
			str(AUTOLOAD_PRIORITY[i]).to_lower()
		):

			return i


	return 1000


# ============================================================
# LOAD INDIVIDUAL AUTOLOAD
# ============================================================

func load_autoload_entry(
	autoload_name: String,
	path: String,
	is_singleton: bool
) -> void:

	if not is_singleton:

		log_msg(
			"Skipping non-singleton autoload: "
			+ autoload_name
		)

		return


	if get_tree().root.has_node(
		autoload_name
	):

		log_msg(
			"Autoload already exists: "
			+ autoload_name
		)

		return


	var clean_path := path

	if clean_path.ends_with(".remap"):
		clean_path = clean_path.trim_suffix(".remap")


	log_msg(
		"Loading autoload: "
		+ autoload_name
		+ " -> "
		+ clean_path
	)


	if not ResourceLoader.exists(clean_path):
		
		log_msg(
			"WARNING: Autoload resource does not exist: "
			+ clean_path
		)
		
		return


	var ext := clean_path.get_extension().to_lower()


	# --------------------------------------------------------
	# GDScript autoload
	# --------------------------------------------------------

	if ext == "gd" or ext == "gdc":

		var script = ResourceLoader.load(
			clean_path
		)


		if script == null:

			log_msg(
				"WARNING: Could not load autoload script: "
				+ clean_path
			)

			return


		if not script is Script:

			log_msg(
				"WARNING: Autoload resource is not a Script: "
				+ clean_path
			)

			return


		var instance = script.new()


		if instance == null:

			log_msg(
				"WARNING: Could not instantiate: "
				+ clean_path
			)

			return


		if not instance is Node:

			log_msg(
				"WARNING: Autoload script does not inherit Node: "
				+ clean_path
			)

			return


		var node := instance as Node

		node.name = autoload_name

		get_tree().root.add_child(node)

		loaded_game_autoloads.append(node)

		log_msg(
			"  Autoload started: "
			+ autoload_name
		)

		return


	# --------------------------------------------------------
	# PackedScene autoload
	# --------------------------------------------------------

	if ext == "tscn" or ext == "scn":

		var resource = ResourceLoader.load(
			clean_path
		)


		if resource == null:

			log_msg(
				"WARNING: Could not load autoload scene: "
				+ clean_path
			)

			return


		if not resource is PackedScene:

			log_msg(
				"WARNING: Autoload is not a PackedScene: "
				+ clean_path
			)

			return


		var packed := resource as PackedScene

		var node := packed.instantiate()


		if node == null:

			log_msg(
				"WARNING: Could not instantiate autoload scene: "
				+ clean_path
			)

			return


		node.name = autoload_name

		get_tree().root.add_child(node)

		loaded_game_autoloads.append(node)

		log_msg(
			"  Autoload scene started: "
			+ autoload_name
		)

		return


	log_msg(
		"WARNING: Unsupported autoload type: "
		+ clean_path
	)


# ============================================================
# CLEAR PREVIOUS AUTOLOADS
# ============================================================

func clear_previous_game_autoloads() -> void:

	for node in loaded_game_autoloads:

		if is_instance_valid(node):

			node.queue_free()


	loaded_game_autoloads.clear()


# ============================================================
# MAIN SCENE DISCOVERY
# ============================================================

func find_game_main_scene(
	config: Dictionary
) -> String:


	# --------------------------------------------------------
	# METHOD 1:
	# The game's actual project configuration.
	# --------------------------------------------------------

	if config.has("application/run/main_scene"):

		var configured_scene = config["application/run/main_scene"]


		if configured_scene is String:

			if configured_scene != "":

				if ResourceLoader.exists(
					configured_scene
				):

					log_msg(
						"Using main_scene from project configuration:"
					)

					log_msg(
						configured_scene
					)

					return configured_scene


	# --------------------------------------------------------
	# METHOD 2:
	# Automatic scene discovery.
	# --------------------------------------------------------

	log_msg(
		"Searching exported PCK for scenes..."
	)


	var scenes: Array[String] = []

	collect_scene_resources(
		"res://",
		scenes
	)


	log_msg(
		"Found "
		+ str(scenes.size())
		+ " scene resources."
	)


	if scenes.is_empty():
		return ""


	for scene_path in scenes:

		log_msg(
			"  SCENE: "
			+ scene_path
		)


	# --------------------------------------------------------
	# Priority Targets
	# --------------------------------------------------------

	var targets := [
		"main.tscn", "mainscene.tscn", "start.tscn", "game.tscn",
		"main.tscn.remap", "mainscene.tscn.remap", "start.tscn.remap", "game.tscn.remap"
	]

	for target in targets:

		for scene_path in scenes:

			if scene_path.get_file().to_lower() == target:

				return scene_path


	# --------------------------------------------------------
	# First scene at root (excluding debug/end)
	# --------------------------------------------------------

	for scene_path in scenes:

		var relative := scene_path.trim_prefix(
			"res://"
		)

		if "/" not in relative:

			var lower_name := scene_path.get_file().to_lower()

			if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):

				return scene_path


	# --------------------------------------------------------
	# Last resort (alphabetical, excluding debug/end)
	# --------------------------------------------------------

	scenes.sort()

	for scene_path in scenes:

		var lower_name := scene_path.get_file().to_lower()

		if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):

			return scene_path


	return scenes[0]


# ============================================================
# SCENE RESOURCE DISCOVERY
# ============================================================

func collect_scene_resources(
	folder_path: String,
	results: Array[String]
) -> void:


	var entries := ResourceLoader.list_directory(
		folder_path
	)


	for entry in entries:

		if entry.ends_with("/"):

			var child_name := entry.trim_suffix("/")

			if child_name == "_hollow":
				continue

			collect_scene_resources(
				folder_path.path_join(
					child_name
				),
				results
			)

			continue


		var lower := entry.to_lower()

		if lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap"):

			var path := folder_path.path_join(
				entry
			)

			if path.ends_with(".remap"):
				path = path.trim_suffix(".remap")

			if not path.to_lower().contains(
				"/_hollow/"
			) and not path.to_lower().ends_with("launcher.tscn"):

				results.append(path)


# ============================================================
# SAVE MANAGEMENT
# ============================================================

func manage_saves(
	next_game: String
) -> void:


	var dir := DirAccess.open(
		"user://"
	)


	if dir == null:

		log_msg(
			"WARNING: Could not open user://"
		)

		return


	# --------------------------------------------------------
	# BACK UP PREVIOUS GAME
	# --------------------------------------------------------

	if FileAccess.file_exists(
		LAST_PLAYED_FILE
	):

		var last_game := FileAccess.get_file_as_string(
			LAST_PLAYED_FILE
		).strip_edges()


		if last_game != "":

			var backup_path := SAVES_DIR.path_join(
				last_game
			)


			if not DirAccess.dir_exists_absolute(
				backup_path
			):

				DirAccess.make_dir_recursive_absolute(
					backup_path
				)


			var current_files := dir.get_files()
			var current_dirs := dir.get_directories()


			for file_name in current_files:

				if file_name in SYSTEM_FILES:
					continue


				if file_name.get_extension().to_lower() == "pck":
					continue


				var source := "user://".path_join(
					file_name
				)

				var destination := backup_path.path_join(
					file_name
				)


				var error := DirAccess.rename_absolute(
					source,
					destination
				)


				if error != OK:

					log_msg(
						"WARNING: Could not move file: "
						+ source
					)


			for directory_name in current_dirs:

				if directory_name in SYSTEM_FILES:
					continue


				var source := "user://".path_join(
					directory_name
				)

				var destination := backup_path.path_join(
					directory_name
				)


				var error := DirAccess.rename_absolute(
					source,
					destination
				)


				if error != OK:

					log_msg(
						"WARNING: Could not move directory: "
						+ source
					)


	# --------------------------------------------------------
	# RESTORE SELECTED GAME
	# --------------------------------------------------------

	var restore_path := SAVES_DIR.path_join(
		next_game
	)


	if DirAccess.dir_exists_absolute(
		restore_path
	):

		var restore_dir := DirAccess.open(
			restore_path
		)


		if restore_dir:

			var restore_files := restore_dir.get_files()
			var restore_dirs := restore_dir.get_directories()


			for file_name in restore_files:

				var source := restore_path.path_join(
					file_name
				)

				var destination := "user://".path_join(
					file_name
				)


				DirAccess.rename_absolute(
					source,
					destination
				)


			for directory_name in restore_dirs:

				var source := restore_path.path_join(
					directory_name
				)

				var destination := "user://".path_join(
					directory_name
				)


				DirAccess.rename_absolute(
					source,
					destination
				)


	# --------------------------------------------------------
	# REMEMBER CURRENT GAME
	# --------------------------------------------------------

	var save_file := FileAccess.open(
		LAST_PLAYED_FILE,
		FileAccess.WRITE
	)


	if save_file:

		save_file.store_string(
			next_game
		)

		save_file.close()


# ============================================================
# RESET LAUNCHER
# ============================================================

func reset_launcher() -> void:

	launch_in_progress = false

	for button in game_buttons:

		if is_instance_valid(button):

			button.disabled = false
