import Foundation

var checks = 0
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

func u32(_ number: UInt32) -> Data { var n = number.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
func u64(_ number: UInt64) -> Data { var n = number.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
func fixture(format: UInt32 = 4, path: String = "project.godot", flags: UInt32 = 0, entryFlags: UInt32 = 0, badOffset: Bool = false, duplicate: Bool = false, extraPaths: [String] = []) -> Data {
    let headerSize: UInt64 = format == 1 ? 84 : (format == 2 ? 96 : 112)
    let payload = Data("config_version=5\n[application]\nrun/main_scene=\"res://Main.tscn\"\n".utf8)
    let paths = [path] + (duplicate ? [path] : extraPaths)
    let entries = UInt32(paths.count)
    let directorySize = 4 + paths.reduce(0) { $0 + 4 + $1.utf8.count + 32 + (format >= 2 ? 4 : 0) }
    let payloadOffset = format <= 2 ? headerSize + UInt64(directorySize) : headerSize
    var directory = u32(entries)
    for name in paths {
        directory += u32(UInt32(name.utf8.count)) + Data(name.utf8)
        directory += u64(badOffset ? UInt64.max : payloadOffset) + u64(UInt64(payload.count)) + Data(repeating: 0, count: 16)
        if format >= 2 { directory += u32(entryFlags) }
    }
    var header = u32(0x43504447) + u32(format) + u32(format == 1 ? 3 : 4) + u32(7) + u32(2)
    if format >= 2 { header += u32(flags) + u64(0) }
    if format >= 3 { header += u64(headerSize + UInt64(payload.count)) }
    header += Data(repeating: 0, count: Int(headerSize) - header.count)
    return format >= 3 ? header + payload + directory : header + directory + payload
}

func check(_ bytes: Data, valid: Bool, _ name: String) throws {
    let url = dir.appendingPathComponent("test.pck")
    try bytes.write(to: url)
    do {
        _ = try PCKInspector.inspect(url)
        guard valid else { fatalError("Accepted invalid pack: \(name)") }
    } catch {
        guard !valid else { fatalError("Rejected valid pack \(name): \(error)") }
    }
    checks += 1
}

for format: UInt32 in [1, 2, 3, 4] { try check(fixture(format: format), valid: true, "format \(format)") }
try check(fixture(path: "res://project.godot"), valid: true, "resource prefix")
try check(fixture(path: "../project.godot"), valid: false, "traversal")
try check(fixture(path: "/project.godot"), valid: false, "absolute path")
try check(fixture(path: "C:\\project.godot"), valid: false, "Windows path")
try check(fixture(path: "Scenes/Only.tscn"), valid: false, "resource-only")
try check(fixture(flags: 1), valid: false, "encrypted directory")
try check(fixture(flags: 4), valid: false, "sparse bundle")
try check(fixture(entryFlags: 1), valid: false, "encrypted file")
try check(fixture(entryFlags: 2), valid: false, "removal patch")
try check(fixture(entryFlags: 4), valid: false, "delta patch")
try check(fixture(badOffset: true), valid: false, "integer overflow")
try check(fixture(duplicate: true), valid: false, "duplicate path")
try check(fixture(path: "game.gdextension"), valid: false, "native resource-only archive still lacks project settings")
try check(fixture(path: "project.binary"), valid: false, "invalid binary settings signature")
let optionalNative = fixture(extraPaths: ["addons/webrtc_native/webrtc_native.gdextension", "addons/webrtc_native/lib/windows.dll"])
try check(optionalNative, valid: true, "Complete project with possibly optional native components")
try check(fixture(extraPaths: ["scripts/game.gde"]), valid: false, "Encrypted scripts require a supported engine and validated key")
try check(fixture(extraPaths: ["scripts/game.cs"]), valid: false, ".NET scripts remain unsupported")
let nativeURL = dir.appendingPathComponent("native.pck")
try optionalNative.write(to: nativeURL)
let nativeInfo = try PCKInspector.inspect(nativeURL)
precondition(nativeInfo.nativeFiles?.count == 2, "Native dependencies must be reported rather than silently ignored")

func compiledFixture(version: UInt32, major: UInt32 = 4) -> Data {
    let headerSize = major == 3 ? 84 : 96
    let files: [(String, Data)] = [
        ("project.godot", Data("config_version=\(major == 3 ? 4 : 5)\n".utf8)),
        ("Main.gdc", Data("GDSC".utf8) + u32(version) + u32(0))
    ]
    let directorySize = 4 + files.reduce(0) { $0 + 4 + $1.0.utf8.count + (major == 3 ? 32 : 36) }
    var directory = u32(UInt32(files.count)), payload = Data()
    for (name, bytes) in files {
        directory += u32(UInt32(name.utf8.count)) + Data(name.utf8)
        directory += u64(UInt64(headerSize + directorySize + payload.count)) + u64(UInt64(bytes.count)) + Data(repeating: 0, count: 16)
        if major != 3 { directory += u32(0) }
        payload += bytes
    }
    var header = u32(0x43504447) + u32(major == 3 ? 1 : 2) + u32(major) + u32(4) + u32(1)
    if major != 3 { header += u32(0) + u64(0) }
    header += Data(repeating: 0, count: headerSize - header.count)
    return header + directory + payload
}
try check(compiledFixture(version: 100), valid: true, "legacy compiled script header")
try check(compiledFixture(version: 101), valid: true, "current compiled script header")
try check(compiledFixture(version: 102), valid: false, "future bytecode rejected before engine startup")
try check(compiledFixture(version: 13, major: 3), valid: true, "Godot 3 current bytecode accepted")
try check(compiledFixture(version: 14, major: 3), valid: false, "Godot 3 future bytecode refused")
try check(compiledFixture(version: 100, major: 3), valid: false, "Wrong APK family hint refused before engine startup")
try check(fixture(extraPaths: ["Main.gdc"]), valid: false, "invalid compiled script signature")
let legacyCompiledURL = dir.appendingPathComponent("compiled.pck")
try compiledFixture(version: 100).write(to: legacyCompiledURL)
let legacyCompiledInfo = try PCKInspector.inspect(legacyCompiledURL)
precondition(legacyCompiledInfo.scriptVersions == [100], "Bytecode versions must be recorded independently of engine metadata")
let encryptedURL = dir.appendingPathComponent("encrypted.pck")
try fixture(format: 1, extraPaths: ["addons/example.gde", "game/Main.gde"]).write(to: encryptedURL)
do {
    _ = try PCKInspector.inspect(encryptedURL)
    fatalError("Encrypted scripts cannot be accepted without an export key")
} catch {
    let reason = error.localizedDescription
    precondition(reason.contains("2 encrypted scripts") && reason.contains("export encryption key") && reason.contains("game/Main.gde") && reason.contains("EXE together with the PCK"), "Godot 3 encryption errors must identify the scripts and original EXE/PCK recovery action")
}
checks += 2
var decryptCalls = 0
let recovered = try PCKInspector.inspect(encryptedURL, decryptScript: { _ in
    decryptCalls += 1
    // Test only the inspector/decrypter contract. The model suite separately
    // exercises actual AES and key discovery with an encrypted fixture.
    return Data("GDSC".utf8) + u32(13) + u32(0)
})
precondition(decryptCalls == 2 && recovered.encryptedScriptCount == 2 && recovered.scriptVersions == [13], "Every encrypted script must be validated and its bytecode recorded")
checks += 1
for version: UInt32 in [14, 100] {
    do {
        _ = try PCKInspector.inspect(encryptedURL, decryptScript: { _ in Data("GDSC".utf8) + u32(version) + u32(0) })
        fatalError("Unsupported decrypted bytecode accepted")
    } catch { precondition(error.localizedDescription.contains("newer Godot 3 bytecode reader")) }
    checks += 1
}
try fixture(extraPaths: ["game/Main.gde"]).write(to: encryptedURL)
do {
    _ = try PCKInspector.inspect(encryptedURL, decryptScript: { _ in
        fatalError("Godot 4 encryption must not use the Godot 3 decrypter")
    })
    fatalError("Unsupported Godot 4 encrypted scripts accepted")
} catch {
    let reason = error.localizedDescription
    precondition(reason.contains("Godot 4") && reason.contains("unencrypted export") && !reason.contains("EXE together with the PCK"), "Unsupported encryption must not suggest Godot 3 EXE recovery")
}
checks += 1
let good = fixture()
for length in 0..<good.count { try check(good.prefix(length), valid: false, "truncated \(length)") }
for file in CommandLine.arguments.dropFirst() {
    let info = try PCKInspector.inspect(URL(fileURLWithPath: file))
    precondition([3, 4].contains(info.major) && info.fileCount > 0)
    print("Real PCK accepted: \(file), Godot \(info.version), format \(info.format)")
    checks += 1
}
print("PCK inspector: \(checks) checks passed")
