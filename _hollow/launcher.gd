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

	# Find the game's actual main scene automatically.
	var main_scene = find_game_main_scene()

	if main_scene == "":
		log_msg("ERROR: Could not determine the game's main scene.")
		reset_launcher_state()
		return

	log_msg("Detected game main scene:")
	log_msg(main_scene)

	# ResourceLoader.exists() understands exported/remapped resources.
	if not ResourceLoader.exists(main_scene):
		log_msg("ERROR: ResourceLoader cannot find:")
		log_msg(main_scene)
		reset_launcher_state()
		return

	log_msg("SUCCESS: Scene exists.")

	var packed_scene = ResourceLoader.load(main_scene)

	if packed_scene == null:
		log_msg("ERROR: Scene exists but could not be loaded.")
		log_msg(main_scene)
		reset_launcher_state()
		return

	if not packed_scene is PackedScene:
		log_msg("ERROR: Resource is not a PackedScene.")
		log_msg(main_scene)
		reset_launcher_state()
		return

	var scene = packed_scene as PackedScene

	if not scene.can_instantiate():
		log_msg("ERROR: PackedScene cannot be instantiated.")
		log_msg(main_scene)
		reset_launcher_state()
		return

	log_msg("SUCCESS: Scene loaded and can be instantiated.")
	log_msg("Starting game...")

	var err = get_tree().change_scene_to_packed(scene)

	if err != OK:
		log_msg(
			"ERROR: Scene change failed. Error code: "
			+ str(err)
		)
		reset_launcher_state()
		return

	log_msg("SUCCESS: Game started.")
	log_msg("========================================")


func find_game_main_scene() -> String:
	log_msg("Searching exported PCK for scenes...")

	var all_scenes: Array[String] = []

	collect_resource_scenes("res://", all_scenes)

	log_msg(
		"ResourceLoader found "
		+ str(all_scenes.size())
		+ " scene resources."
	)

	if all_scenes.is_empty():
		log_msg("No scene resources were found in the PCK.")
		return ""


	# ---------------------------------------------------------
	# Show everything we found in the debug log.
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		log_msg("  SCENE: " + scene_path)


	# ---------------------------------------------------------
	# Priority 1:
	# Exact filename Main.tscn
	# Case-insensitive.
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		if scene_path.get_file().to_lower() == "main.tscn":
			log_msg(
				"Selected Main.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 2:
	# MainScene.tscn
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		if scene_path.get_file().to_lower() == "mainscene.tscn":
			log_msg(
				"Selected MainScene.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 3:
	# Start.tscn
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		if scene_path.get_file().to_lower() == "start.tscn":
			log_msg(
				"Selected Start.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 4:
	# Game.tscn
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		if scene_path.get_file().to_lower() == "game.tscn":
			log_msg(
				"Selected Game.tscn: "
				+ scene_path
			)

			return scene_path


	# ---------------------------------------------------------
	# Priority 5:
	# Root-level scene.
	# ---------------------------------------------------------

	for scene_path in all_scenes:
		var relative_path = scene_path.trim_prefix("res://")

		if "/" not in relative_path:
			if scene_path.get_file().to_lower() != "launcher.tscn":
				log_msg(
					"Using root-level scene: "
					+ scene_path
				)

				return scene_path


	# ---------------------------------------------------------
	# Final fallback:
	# Just use the first scene we found.
	# ---------------------------------------------------------

	log_msg(
		"No conventional main scene name found."
	)

	log_msg(
		"Using first discovered scene: "
		+ all_scenes[0]
	)

	return all_scenes[0]


func collect_resource_scenes(
	folder_path: String,
	results: Array[String]
) -> void:

	var entries = ResourceLoader.list_directory(folder_path)

	for entry in entries:

		# ResourceLoader uses a trailing slash to identify directories.
		if entry.ends_with("/"):
			var directory_name = entry.trim_suffix("/")

			# Don't descend into the player's own namespace.
			if directory_name == "_hollow":
				continue

			var child_path = folder_path.path_join(
				directory_name
			)

			collect_resource_scenes(
				child_path,
				results
			)

		else:
			var lower_name = entry.to_lower()

			# ResourceLoader returns original editor-visible
			# filenames, even when export converted them.
			if lower_name.ends_with(".tscn"):
				var scene_path = folder_path.path_join(entry)

				if not scene_path.to_lower().contains(
					"/_hollow/"
				):
					results.append(scene_path)


func manage_saves(next_game: String) -> void:
	var dir = DirAccess.open("user://")

	if dir == null:
		log_msg(
			"WARNING: Could not open user:// for save management."
		)
		return

	# ---------------------------------------------------------
	# BACK UP CURRENT GAME
	# ---------------------------------------------------------

	if FileAccess.file_exists(LAST_PLAYED_FILE):

		var last_game = FileAccess.get_file_as_string(
			LAST_PLAYED_FILE
		).strip_edges()

		if last_game != "":
			var backup_path = SAVES_DIR.path_join(
				last_game
			)

			if not DirAccess.dir_exists_absolute(
				backup_path
			):
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

				var source = "user://".path_join(
					file_name
				)

				var destination = backup_path.path_join(
					file_name
				)

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

				var source = "user://".path_join(
					directory_name
				)

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

	var restore_path = SAVES_DIR.path_join(
		next_game
	)

	if DirAccess.dir_exists_absolute(
		restore_path
	):

		var restore_dir = DirAccess.open(
			restore_path
		)

		if restore_dir:

			var restore_files = restore_dir.get_files()
			var restore_dirs = restore_dir.get_directories()

			for file_name in restore_files:

				var source = restore_path.path_join(
					file_name
				)

				var destination = "user://".path_join(
					file_name
				)

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
