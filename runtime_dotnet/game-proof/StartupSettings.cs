using Godot;
using Godot.Collections;
using System;

public partial class StartupSettings : Node
{
    public enum Actor { First, Second }
    private static readonly Dictionary<string, Variant> Options = new()
    {
        { "enabled", true }, { "amount", 0.5f },
        { "mix", new Dictionary<string, double> { { "Master", 0.75 }, { "Music", 0.5 } } }
    };
    private static readonly Array<Actor> Actors = new() { Actor.First, Actor.Second };
    private static readonly Dictionary<Actor, Resource> Bodies = new();
    private readonly System.Collections.Generic.Dictionary<Actor, bool> flags = new() { { Actor.First, true } };
    [Export] public Dictionary<string, double> Channels { get; set; } = new() { { "Gain", 1.0 } };
    public static bool Passed { get; private set; }

    public override void _Ready()
    {
        var mix = (Dictionary<string, double>)Options["mix"];
        double sum = 0;
        foreach (var (key, value) in mix) { sum += value; }
        using var body = new Resource();
        Bodies[Actor.First] = body;
        if (sum != 1.25 || Actors.Count != 2 || !flags[Actor.First] || Bodies[Actor.First] != body || Channels["Gain"] != 1.0)
            throw new Exception("Typed startup collections did not round-trip");
        Bodies.Clear();
        Passed = true;
        GD.Print("HOLLOW_TYPED_AUTOLOAD_PASS");
    }
}
