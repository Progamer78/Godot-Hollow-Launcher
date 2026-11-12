import Foundation
import Combine

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

do {
    let folder=URL(fileURLWithPath:"build/archive-tests")
    let pack=folder.appendingPathComponent("encrypted-fixture.pck")
    let recovered=try ExecutableImport.recover(executable:folder.appendingPathComponent("original-fixture.exe"),pack:pack)
    require(recovered.0.major == 3 && recovered.0.encryptedScriptCount == 1 && recovered.0.scriptVersions == [13],"Actual PE discovery and AES validation must accept the original encrypted-script fixture")
    require(recovered.1 == Data((0..<32).map { UInt8($0) }),"Recovered fixture key must match its original runtime data")
    do { _ = try ExecutableImport.inspect(pack,key:Data(repeating:0,count:32)); fatalError("Mismatched executable key accepted") } catch {}
    do { _ = try ExecutableImport.inspect(pack,key:nil); fatalError("Encrypted scripts accepted without original runtime") } catch {}
    var controls=ControlProfile.legacy(directions:"arrows",extras:"")
    var first=JoystickControl();first.identifier=UUID();first.mode="floating";first.zone="left"
    first.up="F13"
    var second=JoystickControl();second.identifier=UUID();second.mode="floating";second.zone="right";second.axis=2
    controls.joystick=first;controls.additionalJoysticks=[second];controls.controller=ControllerProfile();controls.gestures=TouchGestures()
    controls.controller?.enabled=true;controls.controller?.rightMode="mouse";controls.controller?.bindings["A"]="Mouse Left"
    controls.constrain()
    let decoded=try JSONDecoder().decode(ControlProfile.self,from:JSONEncoder().encode(controls))
    require(decoded == controls && decoded.sticks.count == 2 && decoded.sticks[0].up == "F13","Multiple stick identities, custom keys, controller mappings and gestures must persist")
    require(decoded.controller?.mouseEnabled == true && decoded.controller?.target("A") == "Mouse Left","Controller stick mouse and click mappings persist")
    var duplicateControls = decoded
    duplicateControls.buttons[0].id = first.id
    duplicateControls.buttons.append(duplicateControls.buttons[0])
    duplicateControls.additionalJoysticks = [first, second, second]
    duplicateControls.constrain()
    require(duplicateControls.buttons.count == decoded.buttons.count && duplicateControls.sticks.map(\.id) == [first.id, second.id], "Button and stick IDs must be deduplicated independently, retaining distinct control kinds sharing an ID")
    require(duplicateControls.buttons[0].id == duplicateControls.sticks[0].id, "A button ID must not remove a joystick with the same ID")
    let neutral=decoded.controller!.stick(0.01,0)
    let moving=decoded.controller!.stick(0.7,0)
    require(neutral.0 == 0 && moving.0 > 0 && moving.0 < 1,"Physical controller deadzone retains analog strength")
    let storedGame=reopened.games[0]
    let privateFolder=reopened.directory(storedGame.id)
    try FileManager.default.createDirectory(at:privateFolder,withIntermediateDirectories:true)
    let privateKeyFile=privateFolder.appendingPathComponent("script-key.bin")
    try recovered.1!.write(to:privateKeyFile)
    let storedKey=try reopened.scriptKey(storedGame)
    require(storedKey == recovered.1,"Private key is read for the same stable game identity")
    try Data(repeating:0,count:33).write(to:privateKeyFile)
    do { _ = try reopened.scriptKey(storedGame); fatalError("Oversized private key accepted") } catch {}
    try FileManager.default.removeItem(at:privateKeyFile)
    var pinGame=storedGame
    pinGame.savedCheats=[SavedCheat(name:"Coins",label:"/root/Game.coins",type:"int",value:"10")]
    reopened.update(pinGame)
    pinGame.savedCheats?[0].value="9223372036854775807"
    reopened.update(pinGame)
    let editedPins=GameLibrary(storageRoot:storage,savesRoot:temporary.appendingPathComponent("Saves"))
    require(editedPins.games[0].savedCheats?[0].value == "9223372036854775807","Editing a pinned value persists exact integer text")
}
print("Original EXE key discovery, real AES validation, multiple sticks and controller profile persistence passed")

do {
    let folder = URL(fileURLWithPath: "build/archive-tests")
    let zip = temporary.appendingPathComponent("encrypted-game.zip")
    let pack = folder.appendingPathComponent("encrypted-fixture.pck")
    let executable = folder.appendingPathComponent("original-fixture.exe")
    var wrong = try Data(contentsOf: executable)
    wrong.replaceSubrange(0x800..<0x820, with: Data(repeating: 0, count: 32))
    let unrelated = temporary.appendingPathComponent("unrelated.exe")
    try wrong.write(to: unrelated)
    try GPArchive.create(zip.path, files: [pack.path, unrelated.path, executable.path], names: ["download/game.pck", "download/a.exe", "download/z.EXE"])
    let prepared = temporary.appendingPathComponent("zip-game.pck")
    let note = try PackageImport.prepare(zip, destination: prepared)
    let imported = try PackageImport.inspectPrepared(prepared, source: zip, note: note)
    require(imported.key == Data((0..<32).map { UInt8($0) }) && imported.pack.encryptedScriptCount == 1, "ZIP import must skip a mismatched EXE and recover from the matching original EXE")
    require(imported.note?.contains("EXE found in ZIP") == true, "ZIP key recovery must be visible in import metadata")
    let copied = try Data(contentsOf: prepared)
    let original = try Data(contentsOf: pack)
    require(copied == original, "ZIP recovery must not rewrite game data")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { $0.hasPrefix("original-") }
    require(leftovers.isEmpty, "Candidate executables must be removed after ZIP inspection")
    let noEXE = temporary.appendingPathComponent("missing-exe.zip")
    try GPArchive.create(noEXE.path, files: [pack.path], names: ["nested/game.pck"])
    do { _ = try PackageImport.inspectPrepared(prepared, source: noEXE, note: nil); fatalError("Encrypted ZIP without an EXE accepted") }
    catch { require(error.localizedDescription.contains("ZIP") && error.localizedDescription.contains("EXE"), "Missing ZIP companion must have an actionable error") }
    let retained = try PackageImport.inspectPrepared(prepared, source: noEXE, note: nil, existingKey: imported.key)
    require(retained.key == imported.key, "Replacing an encrypted game may reuse its validated private key")
    let mismatch = temporary.appendingPathComponent("mismatch.zip")
    try GPArchive.create(mismatch.path, files: [pack.path, unrelated.path], names: ["game.pck", "game.exe"])
    do { _ = try PackageImport.inspectPrepared(prepared, source: mismatch, note: nil); fatalError("Mismatched ZIP pair accepted") }
    catch { require(error.localizedDescription.contains("No matching script key"), "Mismatched ZIP pair must be refused") }
}
print("ZIP-contained EXE/PCK recovery, wrong/missing companion rejection and original byte preservation passed")

do {
    let identity = UUID(), base = temporary.appendingPathComponent("TextSaves")
    let gameFolder = base.appendingPathComponent(identity.uuidString)
    try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
    let file = gameFolder.appendingPathComponent("stats.json")
    let original = "{\"money\":10,\"large\":9223372036854775807}"
    try Data(original.utf8).write(to: file)
    let vault = SaveVault(root: temporary.appendingPathComponent("TextBackups"), saves: base)
    let formatted = try SaveTextFormat.json(original)
    require(formatted.contains("\n") && formatted.contains("9223372036854775807"), "Pretty printing must retain full 64-bit integers")
    let changed = "{\"money\":999,\"large\":9223372036854775807}"
    try vault.edit(identity, name: "stats.json", original: original, text: changed)
    let edited = try vault.preview(identity, name: "stats.json")
    let snapshots = try vault.snapshots(identity)
    require(edited == changed && snapshots.count == 1, "Text editing must write exact bytes and back up first")
    do { try vault.edit(identity, name: "stats.json", original: changed, text: "{broken"); fatalError("Invalid JSON accepted") } catch {}
    let afterInvalid = try vault.preview(identity, name: "stats.json")
    require(afterInvalid == changed, "Invalid JSON must leave the original save untouched")
    do { try vault.edit(identity, name: "stats.json", original: original, text: original); fatalError("Stale save edit accepted") } catch {}
    let beforeRestore = try vault.preview(identity, name: "stats.json")
    require(beforeRestore == changed, "Stale edits must not overwrite newer progress")
    try vault.restore(identity, snapshot: snapshots[0])
    let restored = try vault.preview(identity, name: "stats.json")
    require(restored == original, "The automatic pre-edit backup must restore the original save")
    try Data([0,1,2]).write(to: gameFolder.appendingPathComponent("state.sav"))
    do { try vault.edit(identity, name: "state.sav", original: "", text: "new"); fatalError("Binary save edited") } catch {}
    do { try vault.edit(identity, name: "../stats.json", original: "", text: "new"); fatalError("Save traversal accepted") } catch {}
}
print("Text save editing, JSON validation/formatting, stale-write rejection and backup restore passed")

do {
    let storage = temporary.appendingPathComponent("RecoveryLibrary"), saves = temporary.appendingPathComponent("RecoverySaves")
    let library = GameLibrary(storageRoot: storage, savesRoot: saves)
    var first = Game(id: UUID(), name: "Alpha", pack: pack)
    first.collection = "RPG"; first.lastPlayed = Date(timeIntervalSince1970: 10)
    var second = Game(id: UUID(), name: "Beta", pack: pack)
    second.favorite = true; second.lastPlayed = Date(timeIntervalSince1970: 20)
    try library.persist([first, second])
    require(LibraryQuery.games(library.games, search: " rpg ", collection: "", favoritesOnly: false, sort: .name).map(\.id) == [first.id], "Search must trim whitespace and include collections")
    require(LibraryQuery.games(library.games, search: "", collection: "", favoritesOnly: true, sort: .recent).map(\.id) == [second.id], "Favorite filtering must retain only favorites")
    require(LibraryQuery.games(library.games, search: "", collection: "", favoritesOnly: false, sort: .recent).map(\.id) == [second.id, first.id], "Recent sort must reflect play time")
    second.name = "Newest edit"; library.update(second)
    try Data("broken library index".utf8).write(to: storage.appendingPathComponent("library.json"))
    let recovered = GameLibrary(storageRoot: storage, savesRoot: saves)
    require(!recovered.readOnly && recovered.notice != nil && recovered.games.map(\.name) == ["Alpha", "Beta"], "A corrupt manifest must recover its previous valid copy without deleting game files")
    let unreadable = try FileManager.default.contentsOfDirectory(atPath: storage.path).filter { $0.hasPrefix("library-unreadable-") }
    require(unreadable.count == 1, "The unreadable manifest must be preserved during recovery")
    try FileManager.default.createDirectory(at: recovered.directory(first.id), withIntermediateDirectories: true)
    try Data("pack fixture".utf8).write(to: recovered.packURL(first))
    let saveFolder = recovered.saveURL(first)
    try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
    let saveFile = saveFolder.appendingPathComponent("progress.txt")
    try Data("keep progress".utf8).write(to: saveFile)
    _ = try recovered.vault.backup(first.id, label: "Manual backup")
    let manifest = storage.appendingPathComponent("library.json")
    let manifestBytes = try Data(contentsOf: manifest)
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    recovered.delete(first)
    require(recovered.games.count == 2 && FileManager.default.fileExists(atPath: recovered.packURL(first).path) && FileManager.default.fileExists(atPath: saveFile.path), "Failed manifest persistence must roll back game/save deletion")
    try FileManager.default.removeItem(at: manifest)
    try manifestBytes.write(to: manifest)
    recovered.delete(first)
    require(recovered.games.map(\.id) == [second.id] && !FileManager.default.fileExists(atPath: saveFolder.path), "Confirmed deletion must remove the selected game and its saves")
    let remaining = try recovered.vault.snapshots(first.id)
    require(remaining.isEmpty, "Confirmed deletion must also remove that game's backups")
    let backup = try JSONDecoder().decode([Game].self, from: Data(contentsOf: storage.appendingPathComponent("library.previous.json")))
    require(backup.map(\.id) == [second.id], "Manifest recovery must not resurrect a deliberately deleted game")
    var controls = ControlProfile.legacy(directions: "arrows", extras: "")
    var one = JoystickControl(); one.mode = "floating"; one.identifier = UUID()
    var two = one; two.identifier = UUID()
    controls.joystick = one; controls.additionalJoysticks = [two]
    controls.setMouseEnabled(true); controls.constrain()
    require(controls.mouseEnabled && controls.sticks.allSatisfy { $0.mode == "fixed" }, "Enabling touch mouse must convert every floating stick, not only the first")
}
print("Library recovery, filtering/sorting, deletion rollback and multi-stick mouse transition passed")

do {
    var gestures = TouchGestures()
    gestures.secondFingerClick = "right"; gestures.constrain()
    let decoded = try JSONDecoder().decode(TouchGestures.self, from: JSONEncoder().encode(gestures))
    require(decoded.secondFingerButton == 2, "Second-finger right click persists")
    gestures.secondFingerClick = "left"; gestures.constrain()
    require(gestures.secondFingerButton == 1, "Second-finger left click is supported")
    gestures.secondFingerClick = "unknown"; gestures.constrain()
    require(gestures.secondFingerButton == nil, "Unknown second-finger modes normalize to off")
    let status = try JSONDecoder().decode(ToolReply.self, from: Data("{\"ok\":true,\"fps\":60,\"frameMs\":16.6667,\"processMs\":2,\"physicsMs\":1,\"engineMemoryBytes\":1048576}".utf8))
    require(status.fps == 60 && status.engineMemoryBytes == 1_048_576 && status.processMs == 2, "Performance HUD decodes typed runtime metrics")
    let oldPin = try JSONDecoder().decode(SavedCheat.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Money\",\"label\":\"/root/Game.money\",\"type\":\"int\",\"value\":\"99\"}".utf8))
    require(oldPin.monitored == nil, "Existing pins migrate with the monitor off")
    var watchedPin = oldPin; watchedPin.monitored = true
    let watchedAgain = try JSONDecoder().decode(SavedCheat.self, from: JSONEncoder().encode(watchedPin))
    require(watchedAgain.monitored == true && watchedAgain.value == "99", "Monitor selection persists without changing the pinned edit value")
    var legacyBoolean = SavedCheat(name: "Flag", label: "/root/Game.flag", type: "bool", value: "True")
    require(legacyBoolean.editorValue == "true" && legacyBoolean.value == "True", "Godot 3 capitalized boolean pins must have a valid picker selection without rewriting the saved pin")
    legacyBoolean.editorValue = "false"
    require(legacyBoolean.value == "false", "Editing a migrated boolean pin updates its reusable value")
    let longPath = "/root/Game/VeryLongNodeName.player.relationships.money"
    var unnamed = SavedCheat(name: longPath, label: longPath, type: "int", value: "1234567890123456789", monitored: true)
    require(unnamed.displayName == "money", "Existing default names use the variable leaf instead of the entire structure")
    require(SavedCheat.defaultName(for: "/root/Game.inventory[2000]") == "inventory[2000]", "Default names retain useful array indices")
    unnamed.name = "  Spending Money  "
    let renamed = try JSONDecoder().decode(SavedCheat.self, from: JSONEncoder().encode(unnamed))
    require(renamed.displayName == "Spending Money" && renamed.label == longPath && renamed.value == "1234567890123456789" && renamed.monitored == true, "Renaming persists without altering target, value or monitor selection")
    unnamed.name = " \n "
    require(unnamed.displayName == "money", "Blank names fall back to a useful short label")
}

do {
    let state = GameToolsState()
    state.query = "money"; state.kind = "number"; state.comparison = "changed"
    state.consoleHistory = ["last expression"]
    let data = Data(#"{"ok":true,"searchStarted":true,"searchKind":"any","searchFilter":"","candidateCount":2505,"page":2,"pageCount":26,"searchSteps":1,"searchUndoCount":1,"rows":[{"object":"123","path":[{"kind":"property","name":"money"}],"label":"/root/Game.money","type":"int","value":"81","previous":"80","frozen":true}]}"#.utf8)
    let reply = try JSONDecoder().decode(ToolReply.self, from: data)
    require(state.receive(reply) && state.rows.first?.previous == "80" && state.rows.first?.frozen == true, "Search state retains typed baseline and freeze data")
    require(state.query == "money" && state.kind == "number" && state.comparison == "changed", "Reopening/refreshing never erases draft combined filters")
    require(state.candidateCount == 2505 && state.page == 2 && state.pageCount == 26, "Visible page is independent from complete candidate count")
    let failed = try JSONDecoder().decode(ToolReply.self, from: Data(#"{"ok":false,"message":"Invalid value"}"#.utf8))
    require(!state.receive(failed) && state.rows.count == 1 && state.candidateCount == 2505 && state.page == 2, "Failed searches leave existing candidates and page intact")
    state.scope = "456"
    require(state.scopeChanged, "Changing scope requires an explicit new search")
    state.receive(reply, restoreFilters: true)
    require(state.kind == "any" && state.query.isEmpty, "Undo can restore the native filter snapshot explicitly")
    let scene = try JSONDecoder().decode(ToolReply.self, from: Data(#"{"ok":true,"node":{"object":"123","name":"Button","path":"/root/Game/Button","className":"Button","scriptPath":"res://button.gd","scenePath":"","visible":true,"processing":false,"inputProcessing":true},"actions":[{"signal":"pressed","method":"buy","targetPath":"/root/Game","targetObject":"456"}]}"#.utf8))
    require(scene.node?.inputProcessing == true && scene.actions?.first?.method == "buy", "Inspector decodes real node and connected method information")

    let stored = temporary.appendingPathComponent("pin-order-library")
    var game = decoded
    let firstPin = SavedCheat(name: "Money", label: "/root/Game.money", type: "int", value: "99", monitored: true)
    let topPin = SavedCheat(name: "Flag", label: "/root/Game.flag", type: "bool", value: "true", monitored: false)
    game.savedCheats = [topPin, firstPin]
    try FileManager.default.createDirectory(at: stored, withIntermediateDirectories: true)
    try JSONEncoder().encode([game]).write(to: stored.appendingPathComponent("library.json"))
    let loaded = GameLibrary(storageRoot: stored, savesRoot: stored.appendingPathComponent("Saves"))
    require(loaded.games.first?.savedCheats?.map(\.id) == [topPin.id, firstPin.id], "Per-game pin ordering survives library reload")
    require(loaded.games.first?.savedCheats?.filter { $0.monitored == true }.map(\.id) == [firstPin.id], "Monitor displays only explicitly selected pins after reload")
    game.savedCheats = [firstPin, topPin]; loaded.update(game)
    let reordered = GameLibrary(storageRoot: stored, savesRoot: stored.appendingPathComponent("Saves"))
    require(reordered.games.first?.savedCheats?.map(\.id) == [firstPin.id, topPin.id] && reordered.games.first?.savedCheats?.last?.monitored == false, "Library update persists new pin ordering without changing monitor choices")
}
print("Persistent search state, pagination, scene inspector and pin ordering/selection passed")

do {
    let state = GameToolsState()
    let numericPool = try JSONDecoder().decode(ToolReply.self, from: Data(#"{"ok":true,"searchStarted":true,"searchKind":"any","searchTypes":["number"],"candidateCount":200000,"rows":[{"object":"123","path":[{"kind":"property","name":"money"}],"label":"/root/Game.money","type":"int","value":"0"}]}"#.utf8))
    state.receive(numericPool)
    state.kind = "number"
    require(!state.needsNewSearch, "A supported type narrows the existing pool")
    state.kind = "bool"
    require(state.needsNewSearch, "Boolean searches must start fresh after a number-only pool, even if it was created with Any type")
    var mixed = numericPool; mixed.searchTypes = ["number", "bool"]
    state.receive(mixed)
    require(!state.needsNewSearch && state.rows.first?.type == "int", "Offscreen boolean candidates remain narrowable using whole-pool metadata, not visible rows")
    state.scope = "456"
    require(state.needsNewSearch, "A scope change explicitly searches the selected scene again")
    state.scope = ""
    var empty = numericPool; empty.candidateCount = 0; empty.rows = []; empty.searchTypes = []
    state.receive(empty)
    require(state.needsNewSearch, "An empty result offers a fresh search rather than narrowing an empty set forever")
    var flags = mixed; flags.searchTypes = ["bool"]; flags.candidateCount = 200003
    state.receive(flags)
    require(!state.needsNewSearch && state.candidateTypes == ["bool"], "A boolean pool is retained for repeated change searches")
}
print("Boolean search type switching, offscreen type availability and empty-pool recovery passed")

do {
    func searchReply(busy: Bool, rows: [ToolStat]?, examined: Int) -> ToolReply {
        var reply = ToolReply(ok: true, message: nil, rows: rows, truncated: false, visited: nil, undoCount: nil)
        reply.searching = busy; reply.searchDiscovery = busy; reply.searchStarted = !busy
        reply.examined = examined; reply.workingMatches = busy ? 0 : 1; reply.candidateCount = busy ? 0 : 1
        return reply
    }
    let row = try JSONDecoder().decode(ToolStat.self, from: Data(#"{"object":"123","path":[{"kind":"property","name":"money"}],"label":"/root/Game.money","type":"int","value":"81"}"#.utf8))
    let state = GameToolsState()
    var calls = 0
    var progressOnlyCalls = 0
    var uiUpdates = 0
    let observer = state.$examined.sink { _ in uiUpdates += 1 }
    state.setSearchActive(true, send: { command in
        require(command["action"] as? String == "continue_search", "Search pump only advances its existing search")
        calls += 1
        if command["progressOnly"] as? Bool == true { progressOnlyCalls += 1 }
        return searchReply(busy: calls < 80, rows: calls == 80 ? [row] : nil, examined: calls * 512)
    })
    state.receive(searchReply(busy: true, rows: [row], examined: 0))
    require(state.rows == [row] && state.discovering, "Initial matches are usable before complete discovery")
    let started = Date()
    while state.searching && Date().timeIntervalSince(started) < 2 {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    require(!state.searching && calls == 80, "80 batches finish within 2 seconds; the old heartbeat needed at least 16 seconds")
    require(state.rows == [row] && state.hasSearch && !state.discovering, "Completion replaces preview with the final result")
    require(progressOnlyCalls > 0 && uiUpdates < calls / 2, "Progress work avoids per-batch row reads and excessive UI publications")
    let afterCompletion = calls
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    require(calls == afterCompletion, "Idle search schedules no additional engine work")
    observer.cancel()
    print("Search scheduling: 80 batches completed in \(Int(Date().timeIntervalSince(started) * 1000)) ms, \(uiUpdates) progress updates")

    let paused = GameToolsState()
    var resumedCalls = 0
    paused.setSearchActive(true, send: { _ in resumedCalls += 1; return searchReply(busy: false, rows: [], examined: 1) })
    paused.receive(searchReply(busy: true, rows: [row], examined: 0))
    paused.setSearchActive(false)
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    require(resumedCalls == 0 && paused.rows == [row] && paused.searching, "Backgrounding invalidates pending callbacks without discarding a search")
    paused.setSearchActive(true)
    let resumeDeadline = Date().addingTimeInterval(1)
    while paused.searching && Date() < resumeDeadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    require(resumedCalls == 1 && !paused.searching && paused.rows.isEmpty, "Foregrounding resumes once and an empty completed result clears preview rows")

    let cancelled = GameToolsState()
    var obsoleteCalls = 0
    cancelled.setSearchActive(true, send: { _ in obsoleteCalls += 1; return searchReply(busy: false, rows: [], examined: 0) })
    cancelled.receive(searchReply(busy: true, rows: [row], examined: 0))
    cancelled.receive(searchReply(busy: false, rows: [], examined: 0))
    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    require(obsoleteCalls == 0, "Cancelling invalidates the queued callback before it can touch the engine")
}
print("Fast yielding search pump, progress throttling, preview retention and lifecycle cancellation passed")
