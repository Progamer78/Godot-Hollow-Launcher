extends SceneTree

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var packer = PCKPacker.new()
	assert(packer.pck_start(args[0]) == OK)
	for name in ["project.godot", "Main.tscn", "Main.cs", "ReentryAvatar.cs", "reentry/Avatar.tscn", "reentry/Nested.tscn"]:
		assert(packer.add_file("res://" + name, "res://" + name) == OK)
	assert(packer.add_file("res://.godot/mono/publish/x86_64/HollowDotnetProof.dll", args[1]) == OK)
	# Minimal original GST2/DXT1 cursor: one 4x4 opaque green block. This proves
	# the native cursor path decodes VRAM compression without reading the GPU.
	var cursor_path = args[0].get_base_dir().path_join("ProofCursor.ctex")
	var cursor = FileAccess.open(cursor_path, FileAccess.WRITE)
	cursor.store_buffer("GST2".to_ascii_buffer())
	for value in [1, 4, 4, 0, 0, 0, 0, 0]: cursor.store_32(value)
	cursor.store_32(0) # DATA_FORMAT_IMAGE
	cursor.store_16(4); cursor.store_16(4); cursor.store_32(0); cursor.store_32(Image.FORMAT_DXT1)
	cursor.store_16(0x07e0); cursor.store_16(0); cursor.store_32(0)
	cursor.close()
	assert(packer.add_file("res://ProofCursor.ctex", cursor_path) == OK)
	# Self-contained Windows exports include CLR/JIT/debugger binaries and a
	# desktop copy of framework assemblies. None may replace the trusted runtime.
	var platform_stub = args[0].get_base_dir().path_join("windows-runtime-placeholder.dll")
	var file = FileAccess.open(platform_stub, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer("MZWindows runtime placeholder; deliberately not a portable assembly".to_utf8_buffer())
	file.close()
	for name in ["coreclr.dll", "mscordaccore_amd64_amd64_8.0.1525.16413.dll", "WindowsBase.dll", "System.IO.Compression.Native.dll", "Microsoft.DiaSymReader.Native.amd64.dll"]:
		assert(packer.add_file("res://.godot/mono/publish/x86_64/" + name, platform_stub) == OK)
	assert(packer.flush() == OK)
	print("HOLLOW_DOTNET_ORIGINAL_PACK_CREATED")
	quit()
