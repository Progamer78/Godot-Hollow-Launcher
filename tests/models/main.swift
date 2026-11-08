import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let id = UUID()
let pack = PackInfo(format: 4, major: 4, minor: 7, patch: 1, fileCount: 10, byteCount: 1000)
// The installed player's first manifest has none of the new optional fields.
let legacy: [String: Any] = [
    "id": id.uuidString, "name": "Existing game", "pack": ["format": 4, "major": 4, "minor": 7, "patch": 1, "fileCount": 10, "byteCount": 1000],
    "runtime": "automatic", "renderer": "project", "showControls": true, "directionKeys": "arrows", "extraKeys": "Space,Shift"
]
let oldManifest = try JSONSerialization.data(withJSONObject: [legacy])
let decoded = try JSONDecoder().decode([Game].self, from: oldManifest)[0]
require(decoded.id == id && decoded.controlProfile == nil, "Old library IDs and optional settings must migrate")
var profile = decoded.controls
require(profile.buttons.count == 8, "Legacy buttons should be retained")
require(Set(profile.buttons.map(\.id)).count == profile.buttons.count, "Buttons must have stable unique IDs")
profile.buttons[0].key = "Z"
profile.buttons[0].label = "Jump"
profile.buttons[0].x = 0.7
profile.buttons[0].y = 0.3
profile.buttons[0].width = 100
profile.mouseEnabled = true
profile.mouseMode = "direct"
profile.joystick = JoystickControl()
profile.joystick?.up = "W"
profile.joystick?.down = "S"
profile.joystick?.left = "A"
profile.joystick?.right = "D"
let save = temporary.appendingPathComponent("Saves/\(id.uuidString)/proof.cfg")
try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("original game save".utf8).write(to: save)
let storage = temporary.appendingPathComponent("Library")
try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
try oldManifest.write(to: storage.appendingPathComponent("library.json"))
let library = GameLibrary(storageRoot: storage, savesRoot: temporary.appendingPathComponent("Saves"))
require(library.saveControls(profile, visible: false, for: id), "Controls should save atomically")
let reopened = GameLibrary(storageRoot: storage, savesRoot: temporary.appendingPathComponent("Saves"))
require(reopened.games[0].controls == profile, "Positions, sizes, mappings and mouse settings must survive reopening")
require(!reopened.games[0].showControls && reopened.games[0].id == id, "Visibility persists without changing game identity")
let savedText = try String(contentsOf: save, encoding: .utf8)
require(savedText == "original game save", "Editing controls must leave game saves untouched")
require(Set(ControlKeys.all).count == ControlKeys.all.count, "Key picker choices must not duplicate IDs")
let portrait = ControlProfile.legacy(directions: "wasd", extras: "Space,Shift", areaWidth: 359, areaHeight: 600)
require(portrait.buttons[0].key == "W" && portrait.buttons[3].key == "D", "Reset must honor direction mapping")
for first in 0..<6 {
    for second in (first + 1)..<6 {
        let a = portrait.buttons[first], b = portrait.buttons[second]
        let separateX = abs(a.x - b.x) * 359 >= (a.width + b.width) / 2
        let separateY = abs(a.y - b.y) * 600 >= (a.height + b.height) / 2
        require(separateX || separateY, "Default portrait direction and action buttons must not overlap")
    }
}
var malformed = profile
malformed.buttons[0].x = .nan
malformed.buttons[0].height = -100
malformed.mouseSensitivity = .infinity
malformed.constrain()
require(malformed.buttons[0].x == 0.5 && malformed.buttons[0].height == 44 && malformed.mouseSensitivity == 1, "Malformed layouts must be constrained")
var native = Game(id: UUID(), name: "Optional extension", pack: pack)
native.pack.nativeFiles = ["addons/webrtc_native/webrtc_native.gdextension"]
require(RuntimeSelection.problem(for: native) != nil, "Native components require explicit fallback choice")
native.allowNativeFallback = true
require(RuntimeSelection.problem(for: native) == nil, "Compatible projects may attempt startup without native components")
native.allowNativeFallback = false
native.pack.nativeFiles = ["addons/limboai/bin/limboai.gdextension"]
require(RuntimeSelection.problem(for: native) == nil, "Statically bundled LimboAI must satisfy its descriptor without loading a pack DLL")
native.pack.nativeFiles?.append("addons/other/other.gdextension")
require(RuntimeSelection.problem(for: native) != nil, "Bundled LimboAI must not bypass unrelated native dependency checks")
native.allowNativeFallback = true
native.pack = PackInfo(format: 1, major: 3, minor: 6, patch: 3, fileCount: 1, byteCount: 1)
require(RuntimeSelection.problem(for: native) == nil, "Godot 3 packs must select the isolated runtime automatically")
native.runtime = "godot4"
require(RuntimeSelection.problem(for: native) != nil, "Native fallback must not bypass runtime-major checks")
native.runtime = "godot3"
require(RuntimeSelection.problem(for: native) == nil, "Matching Godot 3 override is valid")
native.pack = pack
require(RuntimeSelection.problem(for: native) != nil, "Godot 3 override cannot run a Godot 4 pack")
let priorProfile = try JSONSerialization.data(withJSONObject: ["buttons": [], "mouseEnabled": true, "mouseMode": "direct", "mouseSensitivity": 1])
let migratedProfile = try JSONDecoder().decode(ControlProfile.self, from: priorProfile)
require(migratedProfile.joystick == nil && migratedProfile.mouseEnabled, "Installed mouse/control profiles decode without a joystick field")
let stick = JoystickControl()
for selectedAxis in [nil, 0, 2] as [Int?] {
    var original = JoystickControl()
    original.axis = selectedAxis
    var constrained = original
    constrained.constrain()
    require(constrained == original, "Valid and legacy joystick axes must survive normalization unchanged")
    let persisted = try JSONDecoder().decode(JoystickControl.self, from: JSONEncoder().encode(constrained))
    require(persisted == original, "Unset and explicit joystick axes must survive persistence")
}
var invalidAxis = JoystickControl()
invalidAxis.axis = 99
invalidAxis.constrain()
require(invalidAxis.axis == 0, "Unsupported joystick axes must fall back to the left stick")
let correctedAxis = invalidAxis
invalidAxis.constrain()
require(invalidAxis == correctedAxis, "Joystick normalization must be idempotent")
require(stick.keys(dx: 0.05, dy: 0.05).isEmpty, "Stick deadzone releases all directions")
require(stick.keys(dx: -1, dy: 0) == ["Left"], "Stick cardinal direction")
require(stick.keys(dx: 1, dy: -1) == ["Right", "Up"], "Stick diagonals hold two directions")
require(stick.keys(dx: 0, dy: .nan).isEmpty, "Malformed joystick samples must release")
var floating = profile
floating.joystick?.mode = "floating"
floating.mouseEnabled = true
floating.constrain()
require(!floating.mouseEnabled, "Floating joystick and mouse cannot compete for screen drags")
let restoredFloating = try JSONDecoder().decode(ControlProfile.self, from: JSONEncoder().encode(floating))
require(restoredFloating == floating, "Floating mode and remapped directions must persist")
let fitted = GameViewport.frame(width: 390, height: 780, aspect: 16.0 / 9)
require(fitted.width == 390 && abs(fitted.height - 219.375) < 0.001 && fitted.y > 0, "Portrait fits a landscape game without cropping")
let tall = GameViewport.frame(width: 390, height: 780, aspect: 0.25)
require(tall.height == 780 && tall.width == 195 && tall.x > 0, "Tall games fit inside portrait width and height")
let landscape = GameViewport.frame(width: 780, height: 390, aspect: 16.0 / 9)
require(landscape.width == 780 && landscape.height == 390, "Landscape rendering bounds remain full size")
let toolWire = Data("{\"object\":\"18446744073709551615\",\"path\":[{\"kind\":\"property\",\"name\":\"money\"}],\"label\":\"/root/Game.money\",\"type\":\"int\",\"value\":\"9223372036854775807\"}".utf8)
let stat = try JSONDecoder().decode(ToolStat.self, from: toolWire)
require(stat.object == "18446744073709551615" && stat.value == "9223372036854775807", "Game tools must preserve 64-bit identifiers and integer text")
let statReloaded = try JSONDecoder().decode(ToolStat.self, from: JSONEncoder().encode(stat))
require(statReloaded == stat && statReloaded.id == stat.id, "Stat references round trip without changing paths")
require(decoded.pack.scriptVersions == nil, "Old manifests must migrate without script-version metadata")
print("Control profile migration, persisted layouts, key mappings, save preservation and compatibility gating passed")

// Archive importer and save-vault checks run with the actual native MiniZip
// bridge on macOS, including streamed APK wrapping and ordinary ZIP exchange.
do {
    let archiveRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: archiveRoot) }
    let gameID = UUID(), savesRoot = archiveRoot.appendingPathComponent("Saves")
    let gameSaves = savesRoot.appendingPathComponent(gameID.uuidString)
    try FileManager.default.createDirectory(at: gameSaves, withIntermediateDirectories: true)
    let save = gameSaves.appendingPathComponent("save.json")
    try Data("{\"money\":55}".utf8).write(to: save)
    try Data("private diagnostic text".utf8).write(to: gameSaves.appendingPathComponent("player.log"))
    try FileManager.default.createDirectory(at: gameSaves.appendingPathComponent("shader_cache"), withIntermediateDirectories: true)
    try Data("rebuildable GPU cache".utf8).write(to: gameSaves.appendingPathComponent("shader_cache/test.bin"))
    try FileManager.default.createDirectory(at: gameSaves.appendingPathComponent("slots/empty"), withIntermediateDirectories: true)
    let vault = SaveVault(root: archiveRoot.appendingPathComponent("Backups"), saves: savesRoot)
    let expectedSaveBytes = Int64(Data("{\"money\":55}".utf8).count)
    let included = try SafeFiles.children(gameSaves, excluding: ["player.log", "shader_cache"])
    require(included.map { $0.1 } == ["save.json"], "Canonical save paths must preserve relative names and exclusions: \(included.map { $0.1 })")
    // Reproduce /var -> /private/var independently of the runner's temp path.
    // Ancestor aliases are allowed; links inside the save tree remain forbidden.
    let alias = archiveRoot.appendingPathComponent("save-parent-alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: savesRoot)
    let aliasedSaves = alias.appendingPathComponent(gameID.uuidString)
    var aliasedDirectories: [String] = []
    let aliasedFiles = try SafeFiles.children(aliasedSaves, excluding: ["player.log", "shader_cache"], directory: { aliasedDirectories.append($0) })
    require(aliasedFiles.map { $0.1 } == ["save.json"], "Ancestor aliases must not corrupt filenames or bypass exclusions")
    require(Set(aliasedDirectories) == Set(["slots", "slots/empty"]), "Directory names must remain relative through ancestor aliases")
    let copied = archiveRoot.appendingPathComponent("alias-copy")
    let copiedBytes = try SafeFiles.copyTree(aliasedSaves, to: copied, excluding: ["player.log", "shader_cache"])
    let copiedSave = try Data(contentsOf: copied.appendingPathComponent("save.json"))
    require(copiedBytes == expectedSaveBytes && copiedSave == Data("{\"money\":55}".utf8), "Copying through an ancestor alias must retain exact save bytes")
    let copiedFiles = try SafeFiles.children(copied)
    require(copiedFiles.map { $0.1 } == ["save.json"], "Excluded files must not be copied through ancestor aliases")
    let original = try vault.backup(gameID, label: "Manual")
    require(original.bytes == expectedSaveBytes, "Save backups must omit logs and rebuildable shader caches: expected \(expectedSaveBytes), got \(original.bytes)")
    try Data("{\"money\":99}".utf8).write(to: save)
    try vault.restore(gameID, snapshot: original)
    let restored = try String(contentsOf: save, encoding: .utf8)
    require(restored.contains("55"), "Restore must recover original progress")
    require(FileManager.default.fileExists(atPath: gameSaves.appendingPathComponent("slots/empty").path), "Backup restoration must retain empty save directories")
    let restoreHistory = try vault.snapshots(gameID)
    require(restoreHistory.count == 2, "Restore must also preserve the replaced progress")
    let zip = archiveRoot.appendingPathComponent("saves.zip")
    try vault.export(gameID, to: zip)
    try Data("{\"money\":1}".utf8).write(to: save)
    try vault.importArchive(gameID, source: zip)
    let importedPreview = try vault.preview(gameID, name: "save.json")
    require(importedPreview.contains("55"), "Save ZIP transfer round trips original bytes")
    require(FileManager.default.fileExists(atPath: gameSaves.appendingPathComponent("slots/empty").path), "Save ZIP transfer must retain empty directories")
    for _ in 0..<7 { _ = try vault.backup(gameID, label: "Automatic: test") }
    let automatic = try vault.snapshots(gameID).filter { $0.label.hasPrefix("Automatic:") }
    require(automatic.count == 5, "Automatic retention keeps five; manual backups are separate")
    try vault.restore(gameID, snapshot: automatic[automatic.count - 1])
    let restoredOldest = try vault.preview(gameID, name: "save.json")
    require(restoredOldest.contains("55"), "Restoring the oldest automatic backup must stage it before retention prunes it")
    let link = gameSaves.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archiveRoot)
    do { _ = try vault.backup(gameID, label: "Must refuse symlink"); fatalError("Unsafe save links accepted") } catch {}
    try FileManager.default.removeItem(at: link)
    let project = archiveRoot.appendingPathComponent("project.godot")
    try Data("config_version=4\n".utf8).write(to: project)
    let apk = archiveRoot.appendingPathComponent("legacy.apk")
    try GPArchive.create(apk.path, files: [project.path], names: ["assets/project.godot"])
    let wrapped = archiveRoot.appendingPathComponent("legacy.pck")
    _ = try PackageImport.prepare(apk, destination: wrapped)
    let legacy = try PCKInspector.inspect(wrapped)
    require(legacy.major == 3 && legacy.format == 1, "Plaintext Godot 3 APK assets use the matching pack family")
    let executable = archiveRoot.appendingPathComponent("game.exe")
    let bytes = try Data(contentsOf: wrapped)
    var size = UInt64(bytes.count).littleEndian
    var embedded = Data("not an executable; original test fixture\n".utf8) + bytes
    embedded += withUnsafeBytes(of: &size) { Data($0) }; embedded += Data("GDPC".utf8)
    try embedded.write(to: executable)
    let extracted = archiveRoot.appendingPathComponent("extracted.pck")
    _ = try PackageImport.prepare(executable, destination: extracted)
    let extractedBytes = try Data(contentsOf: extracted)
    require(extractedBytes == bytes, "Embedded-PCK import must preserve every pack byte")
    let apk4 = URL(fileURLWithPath: "build/archive-tests/movement-assets.apk")
    if FileManager.default.fileExists(atPath: apk4.path) {
        let output = URL(fileURLWithPath: "build/archive-tests/imported-apk.pck")
        _ = try PackageImport.prepare(apk4, destination: output, engineHint: 4)
        let metadata = try PCKInspector.inspect(output)
        require(metadata.major == 4 && metadata.nativeFiles == nil, "APK import must omit non-asset Android native libraries")
    }
    for name in ControlProfile.presetNames {
        var preset = ControlProfile.preset(name); preset.constrain()
        let migrated = try JSONDecoder().decode(ControlProfile.self, from: JSONEncoder().encode(preset))
        require(migrated == preset, "Shared presets and optional input/accessibility fields must round trip")
    }
    let analog = JoystickControl().analog(dx: 0.7, dy: 0)
    require(analog.0 > 0 && analog.0 < 1 && analog.1 == 0, "Analog sticks retain intermediate strength")
}
print("Native archives, APK assets, embedded PCKs, save backup/restore/transfer/retention and analog/control presets passed")
