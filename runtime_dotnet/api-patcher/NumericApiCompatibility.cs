using Mono.Cecil;
using Mono.Cecil.Cil;

// Managed call signatures include their return type. A float -> double API
// change is source-compatible but previously exported IL still requests float.
// Add forwarding overloads to the trusted API; never rewrite a game's DLLs.
internal static class NumericApiCompatibility
{
    private static bool Same(TypeReference a, TypeReference b) => a.FullName == b.FullName;
    private static bool Numeric(TypeReference a, TypeReference b) =>
        (a.MetadataType == MetadataType.Single && b.MetadataType == MetadataType.Double) ||
        (a.MetadataType == MetadataType.Double && b.MetadataType == MetadataType.Single);

    public static int Add(ModuleDefinition current, ModuleDefinition historical)
    {
        int added = 0;
        foreach (var oldType in historical.Types)
        {
            var type = current.GetType(oldType.FullName);
            if (type == null || type.HasGenericParameters) continue;
            foreach (var old in oldType.Methods.Where(m => m.IsPublic && m.HasBody && !m.IsConstructor && !m.HasGenericParameters))
            {
                var candidates = type.Methods.Where(m => m.IsPublic && m.HasBody && m.Name == old.Name &&
                    m.IsStatic == old.IsStatic && !m.HasGenericParameters && m.Parameters.Count == old.Parameters.Count).ToArray();
                if (candidates.Any(m => Same(m.ReturnType, old.ReturnType) &&
                    m.Parameters.Select(p => p.ParameterType.FullName).SequenceEqual(old.Parameters.Select(p => p.ParameterType.FullName)))) continue;
                var compatible = candidates.Where(m => (Same(m.ReturnType, old.ReturnType) || Numeric(m.ReturnType, old.ReturnType)) &&
                    m.Parameters.Zip(old.Parameters).All(p => Same(p.First.ParameterType, p.Second.ParameterType) || Numeric(p.First.ParameterType, p.Second.ParameterType))).ToArray();
                if (compatible.Length != 1) continue; // No guessed coercions or ambiguous overloads.
                var target = compatible[0];
                var result = Same(target.ReturnType, old.ReturnType) ? target.ReturnType : Primitive(current, old.ReturnType);
                var attributes = old.Attributes & (MethodAttributes.MemberAccessMask | MethodAttributes.HideBySig | MethodAttributes.Static | MethodAttributes.SpecialName);
                var shim = new MethodDefinition(old.Name, attributes, result);
                for (int i = 0; i < old.Parameters.Count; i++)
                {
                    var before = old.Parameters[i];
                    var after = target.Parameters[i];
                    shim.Parameters.Add(new ParameterDefinition(before.Name, ParameterAttributes.None,
                        Same(before.ParameterType, after.ParameterType) ? after.ParameterType : Primitive(current, before.ParameterType)));
                }
                type.Methods.Add(shim);
                var il = shim.Body.GetILProcessor();
                if (!shim.IsStatic) il.Append(Instruction.Create(OpCodes.Ldarg_0));
                for (int i = 0; i < shim.Parameters.Count; i++)
                {
                    il.Append(Instruction.Create(OpCodes.Ldarg, shim.Parameters[i]));
                    if (!Same(shim.Parameters[i].ParameterType, target.Parameters[i].ParameterType))
                        il.Append(Instruction.Create(target.Parameters[i].ParameterType.MetadataType == MetadataType.Double ? OpCodes.Conv_R8 : OpCodes.Conv_R4));
                }
                il.Append(Instruction.Create(target.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, target));
                if (!Same(shim.ReturnType, target.ReturnType))
                    il.Append(Instruction.Create(shim.ReturnType.MetadataType == MetadataType.Single ? OpCodes.Conv_R4 : OpCodes.Conv_R8));
                il.Append(Instruction.Create(OpCodes.Ret));
                added++;
            }
        }
        return added;
    }

    private static TypeReference Primitive(ModuleDefinition module, TypeReference reference) => reference.MetadataType switch
    {
        MetadataType.Single => module.TypeSystem.Single,
        MetadataType.Double => module.TypeSystem.Double,
        _ => throw new InvalidOperationException("Only floating-point API conversions are supported")
    };
}
