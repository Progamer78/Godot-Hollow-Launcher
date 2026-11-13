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
    private bool metadataReentryPassed;

    public override void _Ready()
    {
        using (var animation = new Animation())
        {
            LegacyApiCalls.WriteAnimationLength(animation, 0.75f);
            if (LegacyApiCalls.ReadAnimationLength(animation) != 0.75f || animation.Length != 0.75)
                throw new Exception("Historical C# animation signatures did not resolve");
        }
        GD.Print("HOLLOW_LEGACY_API_PASS");
        // Match desktop games which assume an OpenXR interface always exists,
        // including on a phone without a VR runtime. It must report unavailable.
        var xr = XRServer.FindInterface("OpenXR");
        if (xr.IsInitialized() || xr.Initialize() || xr.GetCapabilities() != 0 || xr.IsPrimary())
            throw new Exception("Unavailable OpenXR interface incorrectly reports VR support");
        if (XRServer.FindInterface("UnregisteredProofInterface") != null)
            throw new Exception("Unknown XR interfaces must still return null");
        GD.Print("HOLLOW_UNAVAILABLE_XR_PASS");
        var discovered = ReentryLoader.Load("res://reentry/Avatar.tscn", "res://reentry/Nested.tscn");
        if (discovered.Count != 2 || ReentryLoader.NestedLoads != 1)
            throw new Exception("Script metadata eagerly initialized the avatar during scene enumeration");
        using (var avatar = discovered[0].Instantiate<ReentryAvatar>())
        {
            if (avatar.RelatedCount() != 1 || ReentryLoader.NestedLoads != 2 || !(bool)avatar.Get("Available")
                || !avatar.HasSignal("ReadyForPlay"))
                throw new Exception("Normal avatar initialization or exported metadata was lost");
        }
        metadataReentryPassed = true;
        GD.Print("HOLLOW_METADATA_REENTRY_PASS");
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
        bool passed = metadataReentryPassed && DoorOpen && Position.X == initial.X + 8 && GetNode("ManagedChild") != null
            && (int)Get("Coins") == 42 && (bool)Get("DoorOpen");
        string bclPath = System.IO.Path.Combine(ProjectSettings.GlobalizePath("user://"), "bcl-proof.txt");
        System.IO.File.WriteAllText(bclPath, "Hollow managed IO");
        passed &= System.IO.File.ReadAllText(bclPath) == "Hollow managed IO";
        using var file = Godot.FileAccess.Open("user://dotnet-proof.json", Godot.FileAccess.ModeFlags.Write);
        if (file == null) throw new Exception("Godot save API did not open the proof record");
        file.StoreString("{\"passed\":" + (passed ? "true" : "false") + ",\"frames\":" + frames
            + ",\"coins\":" + Coins + ",\"godot_game_execution\":true,\"bcl_file_io\":true,\"metadata_reentry\":"
            + (metadataReentryPassed ? "true" : "false") + ",\"unavailable_xr\":true,\"legacy_api\":true}");
        file.Close();
        GD.Print(passed ? "HOLLOW_GODOT_DOTNET_PASS" : "HOLLOW_GODOT_DOTNET_FAIL");
        GetTree().Quit(passed ? 0 : 1);
    }
}
