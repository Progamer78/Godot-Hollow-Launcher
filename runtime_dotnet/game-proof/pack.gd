extends SceneTree

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var packer = PCKPacker.new()
	assert(packer.pck_start(args[0]) == OK)
	for name in ["project.godot", "Main.tscn", "Main.cs"]:
		assert(packer.add_file("res://" + name, "res://" + name) == OK)
	assert(packer.add_file("res://.godot/mono/publish/x86_64/HollowDotnetProof.dll", args[1]) == OK)
	assert(packer.flush() == OK)
	print("HOLLOW_DOTNET_ORIGINAL_PACK_CREATED")
	quit()
