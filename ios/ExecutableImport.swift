import Foundation

enum ExecutableImport {
    static func inspect(_ pack: URL, key: Data?) throws -> PackInfo {
        if let key = key {
            guard key.count == 32 else { throw PackError.invalid("Invalid private script key.") }
            return try PCKInspector.inspect(pack, decryptScript: { bytes in
                try autoreleasepool { try GPArchive.decryptScript(bytes, key: key) }
            })
        }
        return try PCKInspector.inspect(pack)
    }
    static func recover(executable: URL, pack: URL) throws -> (PackInfo, Data?) {
        if let info = try? PCKInspector.inspect(pack) { return (info, nil) }
        let keys = try GPArchive.candidateKeys(executable.path)
        for key in keys {
            if let info = try? inspect(pack, key: key), info.major == 3, (info.encryptedScriptCount ?? 0) > 0 { return (info, key) }
        }
        throw PackError.invalid("No matching script key found. Choose the EXE and PCK from the same original download. Only recognized Godot 3 Windows x64 runtime layouts are supported.")
    }
}
