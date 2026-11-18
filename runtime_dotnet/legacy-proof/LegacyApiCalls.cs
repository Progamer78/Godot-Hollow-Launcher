using Godot;

public static class LegacyApiCalls
{
    // This assembly is compiled against 4.6.1, separately from the 4.7.2 game.
    public static float ReadAnimationLength(Animation animation) => animation.Length;
    public static void WriteAnimationLength(Animation animation, float length) => animation.Length = length;
}
