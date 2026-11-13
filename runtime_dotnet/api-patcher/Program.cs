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
var scope = module.TypeSystem.Object.Scope;
TypeReference TypeRef(string ns, string name, bool value = false) => new(ns, name, module, scope, value);
var typeType = TypeRef("System", "Type");
var methodInfo = TypeRef("System.Reflection", "MethodInfo");
var functionType = TypeRef("System", "Func`1");
var resultType = new GenericParameter("TResult", functionType);
functionType.GenericParameters.Add(resultType);
var function = new GenericInstanceType(functionType);
function.GenericArguments.Add(module.TypeSystem.Object);
var getType = new MethodReference("GetTypeFromHandle", typeType, typeType);
getType.Parameters.Add(new ParameterDefinition(TypeRef("System", "RuntimeTypeHandle", true)));
var createDelegate = new MethodReference("CreateDelegate", TypeRef("System", "Delegate"), methodInfo) { HasThis = true };
createDelegate.Parameters.Add(new ParameterDefinition(typeType));
var invokeDelegate = new MethodReference("Invoke", resultType, function) { HasThis = true };
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
    // Mono's reflection Invoke eagerly initializes the declaring game type.
    // A typed delegate retains ordinary beforefieldinit semantics: metadata
    // inspection need not execute unrelated game static field initializers.
    // Adapt only these four trusted API calls; imported game IL is untouched.
    var il = method.Body.GetILProcessor();
    call.OpCode = OpCodes.Pop; call.Operand = null;
    var cursor = call;
    foreach (var instruction in new[] {
        Instruction.Create(OpCodes.Pop), Instruction.Create(OpCodes.Ldtoken, function),
        Instruction.Create(OpCodes.Call, getType), Instruction.Create(OpCodes.Callvirt, createDelegate),
        Instruction.Create(OpCodes.Castclass, function), Instruction.Create(OpCodes.Callvirt, invokeDelegate) })
    { il.InsertAfter(cursor, instruction); cursor = instruction; }
    method.Body.OptimizeMacros();
    changed++;
}
if (changed != 4) throw new InvalidOperationException("Expected exactly four metadata entry points");
assembly.Write(args[1]);
Console.WriteLine("HOLLOW_METADATA_API: adapted four trusted metadata factories; game assemblies unchanged");
