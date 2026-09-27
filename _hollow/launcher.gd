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
	"res://scripts/globals"
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

	if game_config != null:

		log_msg("Game project.godot found inside PCK.")

		apply_basic_game_settings(game_config)

	else:

		log_msg(
			"No project.godot found inside PCK."
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
# READ PROJECT.GODOT FROM PCK
# ============================================================

func read_game_project_config() -> ConfigFile:

	if not ResourceLoader.exists("res://project.godot"):
		return null


	var config := ConfigFile.new()

	var error := config.load(
		"res://project.godot"
	)


	if error != OK:

		log_msg(
			"WARNING: project.godot exists but could not be read."
		)

		return null


	return config


# ============================================================
# APPLY BASIC PROJECT SETTINGS
#
# We deliberately do NOT try to switch renderer or physics
# engines here. Those are engine-startup settings.
#
# Display scaling can be adjusted safely enough for the
# player's current window.
# ============================================================

func apply_basic_game_settings(
	config: ConfigFile
) -> void:

	var width = config.get_value(
		"display",
		"window/size/viewport_width",
		null
	)

	var height = config.get_value(
		"display",
		"window/size/viewport_height",
		null
	)

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
	config: ConfigFile
) -> bool:

	clear_previous_game_autoloads()


	var found_entries: Array[Dictionary] = []


	# --------------------------------------------------------
	# METHOD 1:
	# Exact autoload list from the game's project.godot
	# --------------------------------------------------------

	if config != null:

		if config.has_section("autoload"):

			var autoload_names := config.get_section_keys(
				"autoload"
			)

			for autoload_name in autoload_names:

				var autoload_value = config.get_value(
					"autoload",
					autoload_name,
					""
				)

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

				log_msg(
					"Using autoload order from project.godot."
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

			var a_name := String(a["name"])
			var b_name := String(b["name"])

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


		if not (
			lower.ends_with(".gd")
			or lower.ends_with(".tscn")
		):
			continue


		var full_path := folder_path.path_join(
			entry
		)

		var file_name := entry.get_file()
		var base_name := file_name.get_basename()


		if base_name == "":
			continue


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
			String(AUTOLOAD_PRIORITY[i]).to_lower()
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


	log_msg(
		"Loading autoload: "
		+ autoload_name
		+ " -> "
		+ path
	)


	# --------------------------------------------------------
	# GDScript autoload
	# --------------------------------------------------------

	if path.get_extension().to_lower() == "gd":

		var script = ResourceLoader.load(
			path
		)


		if script == null:

			log_msg(
				"WARNING: Could not load autoload script: "
				+ path
			)

			return


		if not script is Script:

			log_msg(
				"WARNING: Autoload resource is not a Script: "
				+ path
			)

			return


		var instance = script.new()


		if instance == null:

			log_msg(
				"WARNING: Could not instantiate: "
				+ path
			)

			return


		if not instance is Node:

			log_msg(
				"WARNING: Autoload script does not inherit Node: "
				+ path
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

	if path.get_extension().to_lower() == "tscn":

		var resource = ResourceLoader.load(
			path
		)


		if resource == null:

			log_msg(
				"WARNING: Could not load autoload scene: "
				+ path
			)

			return


		if not resource is PackedScene:

			log_msg(
				"WARNING: Autoload is not a PackedScene: "
				+ path
			)

			return


		var packed := resource as PackedScene

		var node := packed.instantiate()


		if node == null:

			log_msg(
				"WARNING: Could not instantiate autoload scene: "
				+ path
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
		+ path
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
	config: ConfigFile
) -> String:


	# --------------------------------------------------------
	# METHOD 1:
	# The game's actual project.godot.
	# --------------------------------------------------------

	if config != null:

		var configured_scene = config.get_value(
			"application",
			"run/main_scene",
			""
		)


		if configured_scene is String:

			if configured_scene != "":

				if ResourceLoader.exists(
					configured_scene
				):

					log_msg(
						"Using main_scene from project.godot:"
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
	# Priority 1: Main.tscn
	# --------------------------------------------------------

	for scene_path in scenes:

		if scene_path.get_file().to_lower() == "main.tscn":

			return scene_path


	# --------------------------------------------------------
	# Priority 2: MainScene.tscn
	# --------------------------------------------------------

	for scene_path in scenes:

		if (
			scene_path.get_file().to_lower()
			== "mainscene.tscn"
		):

			return scene_path


	# --------------------------------------------------------
	# Priority 3: Start.tscn
	# --------------------------------------------------------

	for scene_path in scenes:

		if scene_path.get_file().to_lower() == "start.tscn":

			return scene_path


	# --------------------------------------------------------
	# Priority 4: Game.tscn
	# --------------------------------------------------------

	for scene_path in scenes:

		if scene_path.get_file().to_lower() == "game.tscn":

			return scene_path


	# --------------------------------------------------------
	# Priority 5: First scene at root
	# --------------------------------------------------------

	for scene_path in scenes:

		var relative := scene_path.trim_prefix(
			"res://"
		)

		if "/" not in relative:

			return scene_path


	# --------------------------------------------------------
	# Last resort
	# --------------------------------------------------------

	scenes.sort()

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


		if entry.to_lower().ends_with(".tscn"):

			var path := folder_path.path_join(
				entry
			)

			if not path.to_lower().contains(
				"/_hollow/"
			):

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
