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
    private bool graphics;

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
        graphics = DisplayServer.GetName() != "headless";
        if (graphics)
        {
            var textures = new Godot.Collections.Array();
            for (int i = 0; i < 5; i++)
            {
                using var image = Image.CreateEmpty(4, 4, false, Image.Format.Rgba8);
                image.Fill(i == 3 ? Colors.Lime : Colors.Red);
                textures.Add(ImageTexture.CreateFromImage(image));
            }
            var shader = new Shader { Code = """
                shader_type canvas_item;
                render_mode unshaded;
                uniform sampler2D Masks[5] : filter_nearest;
                uniform int selected = 3;
                vec4 pick_mask(inout int slot, vec2 uv) { return texture(Masks[slot++], uv); }
                void fragment() {
                    int slot = selected;
                    COLOR = pick_mask(slot, UV);
                    COLOR.g *= float(slot - selected) * 0.25;
                }
                """ };
            var material = new ShaderMaterial { Shader = shader };
            material.SetShaderParameter("Masks", textures);
            AddChild(new ColorRect { Size = new Vector2(128, 128), Color = Colors.White, Material = material });
            AddChild(new ColorRect { Position = new Vector2(150, 0), Size = new Vector2(128, 128),
                Material = new ShaderMaterial { Shader = new Shader { Code = "shader_type canvas_item; render_mode unshaded; void fragment(){COLOR=vec4(0.0,0.25,0.0,1.0);}" } } });
        }
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
        if (graphics)
        {
            using var image = GetViewport().GetTexture().GetImage();
            var pixel = image.GetPixel(32, 32);
            var expected = image.GetPixel(182, 32);
            // Green proves sampler #3 was used; 0.25 proves slot++ ran once.
            passed &= pixel.R < 0.02f && pixel.G > 0.1f && Math.Abs(pixel.G - expected.G) < 0.02f && pixel.B < 0.02f && pixel.A > 0.98f;
            GD.Print("HOLLOW_SAMPLER_PIXEL: " + pixel);
            GD.Print(passed ? "HOLLOW_SAMPLER_ARRAY_RENDER_PASS" : "HOLLOW_SAMPLER_ARRAY_RENDER_FAIL");
            image.SavePng("user://sampler-proof.png");
        }
        using var file = Godot.FileAccess.Open("user://dotnet-proof.json", Godot.FileAccess.ModeFlags.Write);
        if (file == null) throw new Exception("Godot save API did not open the proof record");
        file.StoreString("{\"passed\":" + (passed ? "true" : "false") + ",\"frames\":" + frames
            + ",\"coins\":" + Coins + ",\"godot_game_execution\":true,\"bcl_file_io\":true,\"metadata_reentry\":"
            + (metadataReentryPassed ? "true" : "false") + ",\"unavailable_xr\":true,\"legacy_api\":true,\"sampler_array_rendering\":" + (graphics ? "true" : "false") + "}");
        file.Close();
        GD.Print(passed ? "HOLLOW_GODOT_DOTNET_PASS" : "HOLLOW_GODOT_DOTNET_FAIL");
        GetTree().Quit(passed ? 0 : 1);
    }
}
