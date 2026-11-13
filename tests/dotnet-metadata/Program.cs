using System.Reflection;
using System.Runtime.CompilerServices;
using Hollow.MetadataBridge;

static MethodInfo Factory(Type type, string name) => type.GetMethod(name, BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!;
static void Check(bool passed, string message) { if (!passed) throw new Exception(message); }
var methods = Factory(typeof(GameMetadata), "GetGodotMethodList");
var first = (List<string>)MetadataFactoryInvoker.Invoke(methods)!;
Check(first.SequenceEqual(new[] { "a", "b", "c", "String" }), "Branches, local variables, fields and type tokens");
Check(State.Initializations == 0, "Metadata inspection eagerly initialized the game");
var second = (List<string>)MetadataFactoryInvoker.Invoke(methods)!;
Check(!ReferenceEquals(first, second), "Cache factories, not mutable metadata results");
Check((string)MetadataFactoryInvoker.Invoke(Factory(typeof(GameMetadata), "GetGodotSignalList"))! == "signal", "String literals");
var generic = (Type[])MetadataFactoryInvoker.Invoke(Factory(typeof(GenericMetadata<int>), "GetGodotPropertyDefaultValues"))!;
Check(generic.SequenceEqual(new[] { typeof(int), typeof(List<int>) }), "Closed generic type context");
Check(State.Initializations == 0, "Generic metadata eagerly initialized the game");
InitializeNormally();
Check(State.Initializations == 1, "Normal game initialization must still run");
Check((string)MetadataFactoryInvoker.Invoke(Factory(typeof(ExplicitMetadata), "GetGodotSignalList"))! == "explicit"
    && State.Initializations == 2, "Explicit static constructors keep their semantics");
try { MetadataFactoryInvoker.Invoke(Factory(typeof(FailingMetadata), "GetGodotMethodList")); throw new Exception("Missing factory exception"); }
catch (InvalidOperationException e) when (e.Message == "metadata failure") { }
Console.WriteLine("HOLLOW_METADATA_TESTS_PASS: initialization isolation, branches, tokens, generics, mutable results and exceptions");

[MethodImpl(MethodImplOptions.NoInlining)]
static void InitializeNormally() => GameMetadata.InitializeNormally();

static class State { public static int Initializations; public static int Initialize() => ++Initializations; }
class GameMetadata
{
    private static readonly int Initialized = State.Initialize();
    private static List<string> GetGodotMethodList()
    {
        var result = new List<string>();
        foreach (int value in new[] { 0, 1, 2 })
            result.Add(value switch { 0 => Names.A, 1 => "b", _ => "c" });
        result.Add(typeof(string).Name); return result;
    }
    public static string GetGodotSignalList() => "signal";
    public static void InitializeNormally() => GC.KeepAlive(Initialized);
    private static class Names { public static readonly string A = "a"; }
}
class GenericMetadata<T>
{
    private static readonly int Initialized = State.Initialize();
    public static Type[] GetGodotPropertyDefaultValues() => new[] { typeof(T), typeof(List<T>) };
}
class ExplicitMetadata
{
    static ExplicitMetadata() { State.Initialize(); }
    public static string GetGodotSignalList() => "explicit";
}
class FailingMetadata
{
    public static object GetGodotMethodList() => throw new InvalidOperationException("metadata failure");
}
