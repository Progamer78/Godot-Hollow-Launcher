using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

public static unsafe class HollowManagedProbe
{
    [UnmanagedCallersOnly]
    public static int Add(int a, int b) => a + b;

    // No reference to the independently built game assembly. It is copied to
    // Documents after the runtime starts and loaded as an ordinary import.
    [UnmanagedCallersOnly]
    public static int LoadGame(IntPtr path, delegate* unmanaged<int, int, int> nativeCallback)
    {
        try
        {
            string filename = Marshal.PtrToStringUTF8(path)!;
            var game = Assembly.LoadFrom(filename);
            var method = game.GetType("IndependentGame")!.GetMethod("Run")!;
            int value = (int)method.Invoke(null, null)!;
            return nativeCallback(value, 1);
        }
        catch (Exception e) { Console.Error.WriteLine(e); return -1; }
    }
}
