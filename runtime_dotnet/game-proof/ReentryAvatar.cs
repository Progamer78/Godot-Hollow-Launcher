using Godot;
using System;
using System.Collections.Generic;

// An original regression for scene loading through a shared enumeration buffer.
// Metadata discovery must not eagerly execute this beforefieldinit type's game
// static fields. Instantiating it after discovery must still initialize them.
public partial class ReentryAvatar : Node
{
    private static readonly List<PackedScene> Related = ReentryLoader.Load("res://reentry/Nested.tscn");
    [Export] public bool Available { get; set; } = true;
    [Signal] public delegate void ReadyForPlayEventHandler();
    public int RelatedCount() => Related.Count;
}

public static class ReentryLoader
{
    private static readonly List<string> Pending = new();
    public static int NestedLoads;

    public static List<PackedScene> Load(params string[] paths)
    {
        Pending.Clear(); Pending.AddRange(paths);
        var result = new List<PackedScene>();
        foreach (string path in Pending)
        {
            if (path.EndsWith("Nested.tscn", StringComparison.Ordinal)) NestedLoads++;
            result.Add(ResourceLoader.Load<PackedScene>(path)
                ?? throw new InvalidOperationException("Scene load failed: " + path));
        }
        return result;
    }
}
