using System.Collections.Concurrent;
using System.Reflection;
using System.Reflection.Emit;

namespace Hollow.MetadataBridge;

public static class MetadataFactoryInvoker
{
    private static readonly ConcurrentDictionary<MethodInfo, Func<object?>> Factories = new();
    private static readonly Dictionary<short, OpCode> Codes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
        .Where(f => f.FieldType == typeof(OpCode)).Select(f => (OpCode)f.GetValue(null)!).GroupBy(c => c.Value).ToDictionary(g => g.Key, g => g.First());

    public static object? Invoke(MethodInfo factory)
    {
        if (!factory.IsStatic || factory.GetParameters().Length != 0 || factory.ReturnType.IsValueType
            || factory.Name is not ("GetGodotMethodList" or "GetGodotSignalList" or "GetGodotPropertyList" or "GetGodotPropertyDefaultValues"))
            throw new NotSupportedException("Unexpected Godot metadata factory: " + factory);
        // Explicit static constructors keep their original semantics. Only
        // beforefieldinit metadata can safely avoid eagerly initializing a game.
        if ((factory.DeclaringType!.Attributes & TypeAttributes.BeforeFieldInit) == 0)
            return factory.Invoke(null, null);
        return Factories.GetOrAdd(factory, CopyFactory)();
    }

    private sealed record Instruction(int Offset, OpCode Code, object? Operand);

    private static Func<object?> CopyFactory(MethodInfo factory)
    {
        var body = factory.GetMethodBody() ?? throw new NotSupportedException("Missing Godot metadata factory body");
        if (body.ExceptionHandlingClauses.Count != 0)
            throw new NotSupportedException("Unexpected exception regions in generated Godot metadata");
        byte[] bytes = body.GetILAsByteArray()!;
        var instructions = new List<Instruction>();
        int offset = 0;
        while (offset < bytes.Length)
        {
            int start = offset;
            short value = bytes[offset++];
            if (value == 0xfe) value = (short)(0xfe00 | bytes[offset++]);
            var code = Codes[value];
            object? operand = null;
            switch (code.OperandType)
            {
                case OperandType.InlineNone: break;
                case OperandType.ShortInlineI: operand = (sbyte)bytes[offset++]; break;
                case OperandType.ShortInlineVar: operand = (short)bytes[offset++]; break;
                case OperandType.InlineVar: operand = BitConverter.ToInt16(bytes, offset); offset += 2; break;
                case OperandType.InlineI8: operand = BitConverter.ToInt64(bytes, offset); offset += 8; break;
                case OperandType.ShortInlineR: operand = BitConverter.ToSingle(bytes, offset); offset += 4; break;
                case OperandType.InlineR: operand = BitConverter.ToDouble(bytes, offset); offset += 8; break;
                case OperandType.ShortInlineBrTarget:
                    int relative = (sbyte)bytes[offset++]; operand = offset + relative; break;
                case OperandType.InlineBrTarget:
                    int distance = BitConverter.ToInt32(bytes, offset); offset += 4; operand = offset + distance; break;
                case OperandType.InlineSwitch:
                    int count = BitConverter.ToInt32(bytes, offset); offset += 4;
                    int end = checked(offset + 4 * count);
                    var targets = new int[count];
                    for (int i = 0; i < count; i++, offset += 4) targets[i] = end + BitConverter.ToInt32(bytes, offset);
                    operand = targets; break;
                default: operand = BitConverter.ToInt32(bytes, offset); offset += 4; break;
            }
            instructions.Add(new Instruction(start, code, operand));
        }

        // iOS Mono interprets this IL; no native compilation or imported DLL
        // modification occurs. Its owner is the trusted bridge, so merely
        // reading metadata cannot execute the declaring game's static fields.
        var copy = new DynamicMethod("HollowMetadata_" + factory.Name, factory.ReturnType, Type.EmptyTypes,
            typeof(MetadataFactoryInvoker).Module, skipVisibility: true) { InitLocals = body.InitLocals };
        var il = copy.GetILGenerator();
        foreach (var local in body.LocalVariables) il.DeclareLocal(local.LocalType, local.IsPinned);
        var labels = instructions.ToDictionary(i => i.Offset, _ => il.DefineLabel());
        labels.Add(bytes.Length, il.DefineLabel());
        var module = factory.Module;
        Type[]? typeArguments = factory.DeclaringType!.IsGenericType ? factory.DeclaringType.GetGenericArguments() : null;
        Type[]? methodArguments = factory.IsGenericMethod ? factory.GetGenericArguments() : null;
        foreach (var instruction in instructions)
        {
            il.MarkLabel(labels[instruction.Offset]);
            var code = instruction.Code;
            var operand = instruction.Operand;
            switch (code.OperandType)
            {
                case OperandType.InlineNone: il.Emit(code); break;
                case OperandType.ShortInlineI: il.Emit(code, (sbyte)operand!); break;
                case OperandType.InlineVar:
                case OperandType.ShortInlineVar: il.Emit(code, (short)operand!); break;
                case OperandType.InlineI: il.Emit(code, (int)operand!); break;
                case OperandType.InlineI8: il.Emit(code, (long)operand!); break;
                case OperandType.ShortInlineR: il.Emit(code, (float)operand!); break;
                case OperandType.InlineR: il.Emit(code, (double)operand!); break;
                case OperandType.ShortInlineBrTarget:
                    // Use long branches because member/local emission may change offsets.
                    var longBranch = Codes.Values.First(c => c.Name == code.Name![..^2]);
                    il.Emit(longBranch, labels[(int)operand!]); break;
                case OperandType.InlineBrTarget: il.Emit(code, labels[(int)operand!]); break;
                case OperandType.InlineSwitch: il.Emit(code, ((int[])operand!).Select(t => labels[t]).ToArray()); break;
                case OperandType.InlineString: il.Emit(code, module.ResolveString((int)operand!)); break;
                case OperandType.InlineType: il.Emit(code, module.ResolveType((int)operand!, typeArguments, methodArguments)); break;
                case OperandType.InlineField: il.Emit(code, module.ResolveField((int)operand!, typeArguments, methodArguments)!); break;
                case OperandType.InlineMethod:
                    var method = module.ResolveMethod((int)operand!, typeArguments, methodArguments);
                    if (method is ConstructorInfo constructor) il.Emit(code, constructor);
                    else il.Emit(code, (MethodInfo)method!);
                    break;
                case OperandType.InlineTok:
                    var member = module.ResolveMember((int)operand!, typeArguments, methodArguments);
                    if (member is Type type) il.Emit(code, type);
                    else if (member is FieldInfo field) il.Emit(code, field);
                    else if (member is MethodInfo methodToken) il.Emit(code, methodToken);
                    else if (member is ConstructorInfo constructorToken) il.Emit(code, constructorToken);
                    else throw new NotSupportedException("Unsupported generated metadata token");
                    break;
                default: throw new NotSupportedException("Unsupported generated metadata instruction: " + code);
            }
        }
        il.MarkLabel(labels[bytes.Length]);
        return (Func<object?>)copy.CreateDelegate(typeof(Func<object?>));
    }
}
