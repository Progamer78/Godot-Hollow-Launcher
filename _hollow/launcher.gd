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
var log_file_path := ""


# ============================================================
# LOGGING
# ============================================================

func log_msg(message: String) -> void:
	print(message)
	
	if log_file_path == "":
		return

	var time_dict := Time.get_time_dict_from_system()
	var time_str := str(time_dict.hour).pad_zeros(2) + ":" + str(time_dict.minute).pad_zeros(2) + ":" + str(time_dict.second).pad_zeros(2)
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
	var dt := Time.get_datetime_dict_from_system()
	var ts := str(dt.year) + "-" + str(dt.month).pad_zeros(2) + "-" + str(dt.day).pad_zeros(2) + "_" + str(dt.hour).pad_zeros(2) + "-" + str(dt.minute).pad_zeros(2) + "-" + str(dt.second).pad_zeros(2)
	log_file_path = "user://hollow_run_" + ts + ".log"
	
	log_msg("")
	log_msg("========================================")
	log_msg("=== HOLLOW PLAYER INITIALIZATION ===")
	log_msg("Session Log Created At: " + log_file_path)
	log_msg("Engine Framework: " + Engine.get_version_info().string)
	log_msg("Verifying user directories...")
	log_msg("========================================")

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)
		log_msg("-> Created missing save directory sandbox: " + SAVES_DIR)

	build_ui()


# ============================================================
# LAUNCHER UI
# ============================================================

func build_ui() -> void:
	log_msg("Building interface constraints...")
	
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
# PLAY GAME SEQUENCE
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
	log_msg("--- LAUNCH SEQUENCE INITIATED ---")
	log_msg("Target Payload: " + pck_name)


	var pck_path := "user://".path_join(pck_name)


	# --------------------------------------------------------
	# CHECK FILE
	# --------------------------------------------------------

	if not FileAccess.file_exists(pck_path):

		log_msg("FATAL: PCK payload is missing from local storage.")
		log_msg("Expected Path: " + pck_path)

		reset_launcher()
		return

	log_msg("-> PCK validation passed. File exists.")


	# --------------------------------------------------------
	# SAVE MANAGEMENT
	# --------------------------------------------------------
	
	log_msg("-> Entering save data isolation phase...")
	manage_saves(pck_name)


	# --------------------------------------------------------
	# LOAD PCK
	# --------------------------------------------------------

	log_msg("-> Directing engine to mount virtual file system from PCK...")

	var loaded := ProjectSettings.load_resource_pack(
		pck_path,
		true
	)

	if not loaded:

		log_msg("FATAL: Engine failed to load resource pack. The internal headers may be incompatible.")
		log_msg("Failed Path: " + pck_path)

		reset_launcher()
		return

	log_msg("-> SUCCESS: Payload overlaid onto res:// root.")


	# --------------------------------------------------------
	# READ GAME CONFIGURATION
	# --------------------------------------------------------

	log_msg("-> Beginning internal binary extraction for project settings...")
	var game_config := read_game_project_config()

	if not game_config.is_empty():

		log_msg("-> Config map populated successfully. Passing instructions to viewport scaler...")
		apply_basic_game_settings(game_config)

	else:

		log_msg(
			"-> WARNING: Binary extraction returned empty dictionary. Proceeding via engine fallbacks."
		)


	# --------------------------------------------------------
	# CREATE GAME AUTOLOADS
	# --------------------------------------------------------
	
	log_msg("-> Entering memory allocation for Singleton Managers...")

	var autoloads_ok := setup_game_autoloads(
		game_config
	)

	if not autoloads_ok:
		log_msg(
			"-> WARNING: Memory allocation bypassed. No autoloads discovered."
		)
	else:
		log_msg(
			"-> Autoload node tree construction finalized."
		)


	# --------------------------------------------------------
	# WAIT ONE FRAME
	# --------------------------------------------------------
	
	log_msg("-> Yielding thread to engine processor to trigger Autoload _ready() calls...")
	await get_tree().process_frame


	# --------------------------------------------------------
	# FIND MAIN SCENE
	# --------------------------------------------------------
	
	log_msg("-> Initiating main scene heuristic discovery...")
	var main_scene := find_game_main_scene(
		game_config
	)

	if main_scene == "":

		log_msg(
			"FATAL: Scraper could not resolve an entry point for the game."
		)

		reset_launcher()
		return

	log_msg(
		"-> Entry point resolved to: "
		+ main_scene
	)


	# --------------------------------------------------------
	# VERIFY SCENE
	# --------------------------------------------------------

	if not ResourceLoader.exists(main_scene):

		log_msg(
			"FATAL: Engine reports the resolved scene path does not exist in the mounted res:// virtual memory."
		)

		reset_launcher()
		return

	log_msg("-> Instructing ResourceLoader to fetch PackedScene to memory...")
	var packed_scene = ResourceLoader.load(main_scene)

	if packed_scene == null:

		log_msg(
			"FATAL: PackedScene memory allocation failed. The scene file may be corrupt."
		)

		reset_launcher()
		return

	if not packed_scene is PackedScene:

		log_msg(
			"FATAL: The requested resource is not formatted as a PackedScene."
		)

		reset_launcher()
		return

	var scene := packed_scene as PackedScene

	if not scene.can_instantiate():

		log_msg(
			"FATAL: Scene fails instantiation checks. It is likely missing dependencies."
		)

		reset_launcher()
		return


	log_msg("-> Engine validation successful. Engaging main tree swap...")


	# --------------------------------------------------------
	# START GAME
	# --------------------------------------------------------

	var error := get_tree().change_scene_to_packed(scene)


	if error != OK:

		log_msg(
			"FATAL: Engine blocked the scene transition. Internal Error Code: " + str(error)
		)

		reset_launcher()
		return


	log_msg(
		"-> SUCCESS: Scene tree successfully swapped."
	)

	log_msg("========================================")
	log_msg("--- HANDOFF COMPLETE ---")
	log_msg("========================================")


# ============================================================
# READ CONFIGURATION FROM PCK
# ============================================================

func read_game_project_config() -> Dictionary:

	var settings := {}

	if ResourceLoader.exists("res://project.godot"):
		
		log_msg("-> Parsing text-based project.godot file...")
		var config := ConfigFile.new()

		var error := config.load(
			"res://project.godot"
		)

		if error == OK:
			for section in config.get_sections():
				for key in config.get_section_keys(section):
					settings[section + "/" + key] = config.get_value(section, key)

			log_msg("-> Text map parsed completely.")
			return settings


	if FileAccess.file_exists("res://project.binary"):
		
		log_msg("-> Compiled project.binary detected. Initiating byte sequence read...")

		var file := FileAccess.open("res://project.binary", FileAccess.READ)

		if file:
			var magic := file.get_32()

			if magic == 0x43464745 or magic == 0x47464345:
				log_msg("-> Header magic string matches Godot configuration binary format.")
				var count := file.get_32()
				
				log_msg("-> Loop configured to extract " + str(count) + " variant key-value entries.")

				if count > 0 and count < 65536:
					var parsed := 0
					for i in range(count):

						if file.get_position() >= file.get_length():
							log_msg("-> WARNING: EOF reached prematurely at index: " + str(i))
							break

						var key = file.get_pascal_string()
						var val = file.get_var()

						if key != "" and val != null:
							if typeof(val) == TYPE_DICTIONARY and val.has("value"):
								settings[key] = val["value"]
							else:
								settings[key] = val
							parsed += 1
					
					log_msg("-> Extraction complete. Pulled " + str(parsed) + " configurations.")

			file.close()

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
				"-> Viewport scaling clamped to native bounds: "
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
			"-> Extracted explicit Autoloads from project binary. Forwarding to loader..."
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
		"-> Bypassing binary settings. Commencing deep-scan across virtual res:// paths..."
	)

	var candidates: Array[Dictionary] = []

	for folder in AUTOLOAD_SEARCH_PATHS:

		var dir := DirAccess.open(folder)
		if dir == null:
			continue

		collect_autoload_resources(
			folder,
			candidates
		)


	if candidates.is_empty():

		log_msg(
			"-> Heuristic sweep concluded. No viable Autoload candidate classes detected."
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

	var dir := DirAccess.open(folder_path)
	if dir == null:
		return

	for d in dir.get_directories():
		if d.begins_with(".") or d in ["_hollow", "scenes", "ui"]:
			continue

		var child_path := folder_path.path_join(d)
		collect_autoload_resources(
			child_path,
			results
		)

	for f in dir.get_files():

		var lower := f.to_lower()
		var valid_script := lower.ends_with(".gd") or lower.ends_with(".gdc") or lower.ends_with(".gd.remap")
		var valid_scene := lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap")

		if not (valid_script or valid_scene):
			continue

		var full_path := folder_path.path_join(f)
		if full_path.ends_with(".remap"):
			full_path = full_path.trim_suffix(".remap")

		var file_name := f
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
		return

	if get_tree().root.has_node(
		autoload_name
	):
		return


	var clean_path := path

	if clean_path.ends_with(".remap"):
		clean_path = clean_path.trim_suffix(".remap")


	if not ResourceLoader.exists(clean_path):
		log_msg(
			"-> WARNING: Autoload map references dead path: "
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

		if script == null or not script is Script:
			log_msg(
				"-> ERROR: Resource is not formatted as an executable script: "
				+ clean_path
			)
			return

		var base_type = script.get_instance_base_type()
		var instance = ClassDB.instantiate(base_type)
		
		if instance == null or not instance is Node:
			log_msg(
				"-> ERROR: Base C++ class '" + str(base_type) + "' does not inherit Node: " 
				+ clean_path
			)
			return

		var node := instance as Node
		node.name = autoload_name
		node.set_script(script)

		get_tree().root.add_child(node)
		loaded_game_autoloads.append(node)

		log_msg(
			"-> Active Singleton Generated: [" + autoload_name + "] from " + clean_path
		)

		return


	# --------------------------------------------------------
	# PackedScene autoload
	# --------------------------------------------------------

	if ext == "tscn" or ext == "scn":

		var resource = ResourceLoader.load(
			clean_path
		)

		if resource == null or not resource is PackedScene:
			log_msg(
				"-> ERROR: Resource format mismatch. PackedScene expected: "
				+ clean_path
			)
			return

		var packed := resource as PackedScene

		var node := packed.instantiate()

		if node == null:
			log_msg(
				"-> ERROR: Scene instantiation failed. Dependencies missing: "
				+ clean_path
			)
			return

		node.name = autoload_name

		get_tree().root.add_child(node)

		loaded_game_autoloads.append(node)

		log_msg(
			"-> Active Singleton Scene Added: [" + autoload_name + "] from " + clean_path
		)

		return


	log_msg(
		"-> WARNING: Extension bypassed by compiler validation: "
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
						"-> Project memory pointer successfully acquired entry scene via config dictionary:"
					)

					return configured_scene


	# --------------------------------------------------------
	# METHOD 2:
	# Automatic scene discovery.
	# --------------------------------------------------------

	log_msg(
		"-> Initiating aggressive directory sweep for .tscn files..."
	)


	var scenes: Array[String] = []

	collect_scene_resources(
		"res://",
		scenes
	)


	log_msg(
		"-> Scan verified "
		+ str(scenes.size())
		+ " executable scenes."
	)


	if scenes.is_empty():
		return ""


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
				log_msg("-> Priority heuristic selected matching target.")
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
				log_msg("-> Root directory heuristic selected primary layout.")
				return scene_path


	# --------------------------------------------------------
	# Last resort (alphabetical, excluding debug/end)
	# --------------------------------------------------------

	scenes.sort()

	for scene_path in scenes:

		var lower_name := scene_path.get_file().to_lower()

		if not ("debug" in lower_name or "end" in lower_name or "test" in lower_name):
			log_msg("-> Alphabetical sorting heuristic selected fallback layout.")
			return scene_path


	return scenes[0]


# ============================================================
# SCENE RESOURCE DISCOVERY
# ============================================================

func collect_scene_resources(
	folder_path: String,
	results: Array[String]
) -> void:

	var dir := DirAccess.open(folder_path)
	if dir == null:
		return

	for d in dir.get_directories():

		if d.begins_with(".") or d == "_hollow":
			continue

		var child_path := folder_path.path_join(d)
		collect_scene_resources(
			child_path,
			results
		)

	for f in dir.get_files():

		var lower := f.to_lower()

		if lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".tscn.remap"):

			var path := folder_path.path_join(f)

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
			"-> WARNING: Core operating system blocked user:// write permissions."
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
			var backup_count := 0


			for file_name in current_files:

				if file_name in SYSTEM_FILES:
					continue
					
				if file_name.begins_with("hollow_run_") and file_name.ends_with(".log"):
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


				if error == OK:
					backup_count += 1


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


				if error == OK:
					backup_count += 1
					
			log_msg("-> Archival system secured " + str(backup_count) + " file blocks to " + backup_path)


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
			var restore_count := 0


			for file_name in restore_files:

				var source := restore_path.path_join(
					file_name
				)

				var destination := "user://".path_join(
					file_name
				)


				var error := DirAccess.rename_absolute(
					source,
					destination
				)
				
				if error == OK:
					restore_count += 1


			for directory_name in restore_dirs:

				var source := restore_path.path_join(
					directory_name
				)

				var destination := "user://".path_join(
					directory_name
				)


				var error := DirAccess.rename_absolute(
					source,
					destination
				)
				
				if error == OK:
					restore_count += 1
					
			log_msg("-> Save allocation system restored " + str(restore_count) + " files to operational scope.")


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
