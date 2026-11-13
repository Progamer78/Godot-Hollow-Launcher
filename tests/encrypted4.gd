extends SceneTree

func _initialize():
    var args = OS.get_cmdline_user_args()
    assert(args.size() == 1)
    var output = args[0]
    var key = PackedByteArray()
    for i in range(32): key.append(i)
    for mode in ["directory", "files", "both", "csharp", "zero"]:
        var encrypted_directory = mode != "files"
        var encrypted_files = mode != "directory"
        var packer = PCKPacker.new()
        var hex_key = key.hex_encode() if mode != "zero" else "0".repeat(64)
        assert(packer.pck_start(output.path_join("encrypted4-" + mode + ".pck"), 32, hex_key, encrypted_directory) == OK)
        var files = {
            "project.godot": "config_version=5\n[application]\nconfig/name=\"Encrypted Four Proof\"\nrun/main_scene=\"res://Main.tscn\"\n[debug]\nfile_logging/enable_file_logging=false\n",
            "Main.tscn": "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://Main.gd\" id=\"1\"]\n[node name=\"EncryptedProof\" type=\"Node\"]\nscript = ExtResource(\"1\")\n",
            "Main.gd": "extends Node\nfunc _ready():\n    print(\"PLAYER_ENCRYPTED_FOUR_PROOF PASS\")\n    get_tree().quit()\n"
        }
        if mode == "csharp": files["Game.cs"] = "using Godot; public partial class Game : Node {}"
        for name in files:
            assert(packer.add_file_from_buffer("res://" + name, files[name].to_utf8_buffer(), encrypted_files) == OK)
        assert(packer.flush() == OK)
    print("PLAYER_ENCRYPTED_FOUR_FIXTURES PASS")
    quit()
