extends Control

const SAVES_DIR = "user://_hollow_saves"
const LAST_PLAYED_FILE = "user://_last_played.txt"
const LOG_PATH = "user://debug_log.txt"

const SYSTEM_FILES = [
	"_hollow_saves",
	"_last_played.txt",
	"debug_log.txt"
]

var launch_in_progress := false
var game_buttons: Array[Button] = []


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


func _ready() -> void:
	log_msg("=== Launcher Started ===")

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	build_ui()


func build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	add_child(vbox)

	var title = Label.new()
	title.text = "Godot iOS Player\nSelect a .pck game to play."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var dir = DirAccess.open("user://")

	if dir:
		var files = dir.get_files()

		for file_name in files:
			if file_name.get_extension().to_lower() == "pck":
				var btn = Button.new()
				btn.text = "Play: " + file_name
				btn.custom_minimum_size = Vector2(300, 60)

				btn.pressed.connect(
					_on_play_pressed.bind(file_name)
				)

				vbox.add_child(btn)
				game_buttons.append(btn)

	if game_buttons.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No .pck games found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_label)


func _on_play_pressed(pck_name: String) -> void:
	if launch_in_progress:
		return

	launch_in_progress = true

	for button in game_buttons:
		button.disabled = true

	log_msg("")
	log_msg("========================================")
	log_msg("--- PLAY BUTTON PRESSED ---")
	log_msg("Target PCK: " + pck_name)

	var pck_path = "user://".path_join(pck_name)

	if not FileAccess.file_exists(pck_path):
		log_msg("ERROR: PCK file does not exist:")
		log_msg(pck_path)
		reset_launcher_state()
		return

	log_msg("PCK file exists.")

	# Save management happens before mounting the game.
	manage_saves(pck_name)

	log_msg("Loading PCK...")

	var success = ProjectSettings.load_resource_pack(
		pck_path,
		true
	)

	if not success:
		log_msg("ERROR: Failed to load PCK.")
		log_msg("Path: " + pck_path)
		reset_launcher_state()
		return

	log_msg("SUCCESS: PCK loaded into memory.")

	# Find the game's real entry scene automatically.
	var main_scene = find_game_main_scene()

	if main_scene == "":
		log_msg("ERROR: Could not determine the game's main scene.")
		log_msg("No usable project.godot main_scene was found,")
		log_msg("and no suitable Main.tscn could be discovered.")

		reset_launcher_state()
		return

	log_msg("Detected game main scene:")
	log_msg(main_scene)

	# Verify that Godot can actually see the scene.
	if not ResourceLoader.exists(main_scene):
		log_msg("ERROR: ResourceLoader says the scene does not exist:")
		log_msg(main_scene)

		reset_launcher_state()
		return

	log_msg("Scene exists in mounted PCK.")

	# Load it explicitly so we can report a useful error
	# instead of only getting ERR_CANT_OPEN from change_scene.
	var packed_scene = ResourceLoader.load(main_scene)

	if packed_scene == null:
		log_msg("ERROR: Scene exists but could not be loaded:")
		log_msg(main_scene)

		reset_launcher_state()
		return

	if not packed_scene is PackedScene:
		log_msg("ERROR: Detected file is not a PackedScene:")
		log_msg(main_scene)

		reset_launcher_state()
		return

	var scene = packed_scene as PackedScene

	if not scene.can_instantiate():
		log_msg("ERROR: PackedScene cannot be instantiated:")
		log_msg(main_scene)

		reset_launcher_state()
		return

	log_msg("SUCCESS: Main scene loaded.")
	log_msg("Starting game...")

	var err = get_tree().change_scene_to_packed(scene)

	if err != OK:
		log_msg(
			"ERROR: Could not change to game scene. Error code: "
			+ str(err)
		)
		reset_launcher_state()
		return

	log_msg("SUCCESS: Game started.")
	log_msg("========================================")


func find_game_main_scene() -> String:
	log_msg("Searching for game's main scene...")

	# ---------------------------------------------------------
	# METHOD 1:
	# Read the game's own project.godot if it was included
	# in the exported PCK.
	# ---------------------------------------------------------

	var project_config = ConfigFile.new()
	var project_error = project_config.load("res://project.godot")

	if project_error == OK:
		var configured_scene = project_config.get_value(
			"application",
			"run/main_scene",
			""
		)

		if configured_scene is String and configured_scene != "":
			log_msg(
				"Found main scene in game's project.godot: "
				+ configured_scene
			)

			if ResourceLoader.exists(configured_scene):
				return configured_scene

			log_msg(
				"WARNING: project.godot specified a scene that "
				+ "could not be loaded: "
				+ configured_scene
			)
	else:
		log_msg("Game project.godot was not available.")


	# ---------------------------------------------------------
	# METHOD 2:
	# Search the mounted PCK recursively for Main.tscn.
	#
	# This handles your current game:
	#
	# res://scenes/Main.tscn
	#
	# and also things like:
	#
	# res://Main.tscn
	# res://game/Main.tscn
	# res://Scenes/main.tscn
	# ---------------------------------------------------------

	var all_scenes: Array[String] = []

	collect_tscn_files("res://", all_scenes)

	log_msg(
		"Found "
		+ str(all_scenes.size())
		+ " .tscn files while searching."
	)

	if all_scenes.is_empty():
		return ""


	# Normalize and sort so the result is deterministic.
	all_scenes.sort_custom(
		func(a: String, b: String) -> bool:
			return a.to_lower() < b.to_lower()
	)


	# ---------------------------------------------------------
	# Priority 1:
	# Exact filename "main.tscn" / "Main.tscn"
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		var file_name = scene_path.get_file().to_lower()

		if file_name == "main.tscn":
			log_msg(
				"Auto-detected Main.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 2:
	# Anything named MainScene.tscn
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		var file_name = scene_path.get_file().to_lower()

		if file_name == "mainscene.tscn":
			log_msg(
				"Auto-detected MainScene.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 3:
	# Anything named Start.tscn
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		var file_name = scene_path.get_file().to_lower()

		if file_name == "start.tscn":
			log_msg(
				"Auto-detected Start.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 4:
	# A root-level TSCN.
	#
	# We avoid launcher.tscn because that's the player itself.
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		var relative_path = scene_path.trim_prefix("res://")

		if "/" not in relative_path:
			if scene_path.get_file().to_lower() != "launcher.tscn":
				log_msg(
					"Using root-level scene as fallback: "
					+ scene_path
				)

				return scene_path


	log_msg("No suitable scene found.")

	return ""


func collect_tscn_files(folder_path: String, results: Array[String]) -> void:
	var dir = DirAccess.open(folder_path)

	if dir == null:
		return

	var files = dir.get_files()

	for file_name in files:
		if file_name.get_extension().to_lower() == "tscn":
			var full_path = folder_path.path_join(file_name)

			if not full_path.to_lower().contains(
				"/_hollow/"
			):
				results.append(full_path)

	var directories = dir.get_directories()

	for directory_name in directories:
		# Ignore hidden/internal Godot directories.
		if directory_name.begins_with("."):
			continue

		var child_path = folder_path.path_join(directory_name)

		collect_tscn_files(child_path, results)


func manage_saves(next_game: String) -> void:
	var dir = DirAccess.open("user://")

	if dir == null:
		log_msg("WARNING: Could not open user:// for save management.")
		return

	# ---------------------------------------------------------
	# BACK UP CURRENT GAME
	# ---------------------------------------------------------

	if FileAccess.file_exists(LAST_PLAYED_FILE):
		var last_game = FileAccess.get_file_as_string(
			LAST_PLAYED_FILE
		).strip_edges()

		if last_game != "":
			var backup_path = SAVES_DIR.path_join(last_game)

			if not DirAccess.dir_exists_absolute(backup_path):
				DirAccess.make_dir_recursive_absolute(
					backup_path
				)

			var current_files = dir.get_files()
			var current_dirs = dir.get_directories()

			for file_name in current_files:
				if file_name in SYSTEM_FILES:
					continue

				if file_name.get_extension().to_lower() == "pck":
					continue

				var source = "user://".path_join(file_name)
				var destination = backup_path.path_join(file_name)

				var error = DirAccess.rename_absolute(
					source,
					destination
				)

				if error != OK:
					log_msg(
						"WARNING: Could not move file "
						+ source
						+ " -> "
						+ destination
						+ " Error: "
						+ str(error)
					)

			for directory_name in current_dirs:
				if directory_name in SYSTEM_FILES:
					continue

				var source = "user://".path_join(directory_name)
				var destination = backup_path.path_join(
					directory_name
				)

				var error = DirAccess.rename_absolute(
					source,
					destination
				)

				if error != OK:
					log_msg(
						"WARNING: Could not move directory "
						+ source
						+ " -> "
						+ destination
						+ " Error: "
						+ str(error)
					)


	# ---------------------------------------------------------
	# RESTORE SELECTED GAME
	# ---------------------------------------------------------

	var restore_path = SAVES_DIR.path_join(next_game)

	if DirAccess.dir_exists_absolute(restore_path):
		var restore_dir = DirAccess.open(restore_path)

		if restore_dir:
			var restore_files = restore_dir.get_files()
			var restore_dirs = restore_dir.get_directories()

			for file_name in restore_files:
				var source = restore_path.path_join(file_name)
				var destination = "user://".path_join(file_name)

				var error = DirAccess.rename_absolute(
					source,
					destination
				)

				if error != OK:
					log_msg(
						"WARNING: Could not restore file "
						+ source
						+ " -> "
						+ destination
						+ " Error: "
						+ str(error)
					)

			for directory_name in restore_dirs:
				var source = restore_path.path_join(
					directory_name
				)
				var destination = "user://".path_join(
					directory_name
				)

				var error = DirAccess.rename_absolute(
					source,
					destination
				)

				if error != OK:
					log_msg(
						"WARNING: Could not restore directory "
						+ source
						+ " -> "
						+ destination
						+ " Error: "
						+ str(error)
					)


	# ---------------------------------------------------------
	# MARK GAME AS LAST PLAYED
	# ---------------------------------------------------------

	var save_file = FileAccess.open(
		LAST_PLAYED_FILE,
		FileAccess.WRITE
	)

	if save_file:
		save_file.store_string(next_game)
		save_file.close()


func reset_launcher_state() -> void:
	launch_in_progress = false

	for button in game_buttons:
		if is_instance_valid(button):
			button.disabled = false
