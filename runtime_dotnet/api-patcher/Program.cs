using Mono.Cecil;
using Mono.Cecil.Cil;
using Mono.Cecil.Rocks;

if (args.Length != 2) throw new ArgumentException("Expected trusted GodotSharp input and output paths");
using var assembly = AssemblyDefinition.ReadAssembly(args[0]);
var module = assembly.MainModule;
if (assembly.Name.Name != "GodotSharp" || assembly.Name.Version != new Version(4, 7, 2, 0) || assembly.Name.HasPublicKey)
    throw new InvalidOperationException("Only the matching unsigned trusted GodotSharp API may be adapted");
var bridge = module.GetType("Godot.Bridge.ScriptManagerBridge")
    ?? throw new InvalidOperationException("Script bridge not found");
string helperPath = Path.Combine(AppContext.BaseDirectory, "Hollow.MetadataBridge.dll");
using var helper = AssemblyDefinition.ReadAssembly(helperPath);
var invokeFactory = module.ImportReference(helper.MainModule.GetType("Hollow.MetadataBridge.MetadataFactoryInvoker")
    .Methods.Single(m => m.Name == "Invoke"));
var names = new HashSet<string> { "GetSignalListForType", "GetMethodListForType", "GetPropertyInfoListForType", "GetPropertyDefaultValuesForType" };
int changed = 0;
foreach (var method in bridge.Methods.Where(m => names.Contains(m.Name)))
{
    method.Body.SimplifyMacros();
    var calls = method.Body.Instructions.Where(i => i.OpCode == OpCodes.Callvirt && i.Operand is MethodReference r
        && r.Name == "Invoke" && r.DeclaringType.FullName == "System.Reflection.MethodBase").ToArray();
    if (calls.Length != 1) throw new InvalidOperationException("Unexpected metadata invocation layout: " + method.Name);
    var call = calls[0];
    if (call.Previous.OpCode != OpCodes.Ldnull || call.Previous.Previous.OpCode != OpCodes.Ldnull)
        throw new InvalidOperationException("Metadata invocation is not a parameterless static method");
    // Run only the generated metadata body in a trusted interpreter thunk.
    // Both reflection and ordinary delegates eagerly initialize game types on
    // Mono. Imported assemblies and normal game initialization stay unchanged.
    var il = method.Body.GetILProcessor();
    call.OpCode = OpCodes.Pop; call.Operand = null;
    var cursor = call;
    foreach (var instruction in new[] { Instruction.Create(OpCodes.Pop), Instruction.Create(OpCodes.Call, invokeFactory) })
    { il.InsertAfter(cursor, instruction); cursor = instruction; }
    method.Body.OptimizeMacros();
    changed++;
}
if (changed != 4) throw new InvalidOperationException("Expected exactly four metadata entry points");
assembly.Write(args[1]);
File.Copy(helperPath, Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[1]))!, "Hollow.MetadataBridge.dll"), overwrite: true);
Console.WriteLine("HOLLOW_METADATA_API: adapted four trusted metadata factories; game assemblies unchanged");
