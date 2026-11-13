using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class Main : Node2D
{
    [Export] public int Coins { get; set; } = 40;
    [Export] public bool DoorOpen { get; set; } = false;
    private int frames;
    private Vector2 initial;

    public override void _Ready()
    {
        initial = new Vector2(3, 4);
        Position = initial;
        AddChild(new Node { Name = "ManagedChild" });
        GD.Print("HOLLOW_GODOT_DOTNET_READY: original C# scene instantiated");
    }

    public override void _Process(double delta)
    {
        Position += Vector2.Right;
        if (++frames != 8) return;
        var values = new Dictionary<string, int> { ["coins"] = Coins, ["bonus"] = 2 };
        Coins = values.Values.Sum(); DoorOpen = Coins == 42;
        bool passed = DoorOpen && Position.X == initial.X + 8 && GetNode("ManagedChild") != null
            && (int)Get("Coins") == 42 && (bool)Get("DoorOpen");
        string bclPath = System.IO.Path.Combine(ProjectSettings.GlobalizePath("user://"), "bcl-proof.txt");
        System.IO.File.WriteAllText(bclPath, "Hollow managed IO");
        passed &= System.IO.File.ReadAllText(bclPath) == "Hollow managed IO";
        using var file = Godot.FileAccess.Open("user://dotnet-proof.json", Godot.FileAccess.ModeFlags.Write);
        if (file == null) throw new Exception("Godot save API did not open the proof record");
        file.StoreString("{\"passed\":" + (passed ? "true" : "false") + ",\"frames\":" + frames
            + ",\"coins\":" + Coins + ",\"godot_game_execution\":true,\"bcl_file_io\":true}");
        file.Close();
        GD.Print(passed ? "HOLLOW_GODOT_DOTNET_PASS" : "HOLLOW_GODOT_DOTNET_FAIL");
        GetTree().Quit(passed ? 0 : 1);
    }
}
