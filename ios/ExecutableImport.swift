import Foundation

enum ExecutableImport {
    static func inspect(_ pack: URL, key: Data?) throws -> PackInfo {
        if let key = key {
            guard key.count == 32 else { throw PackError.invalid("Invalid private script key.") }
            return try PCKInspector.inspect(pack, decryptScript: { bytes in
                try autoreleasepool { try GPArchive.decryptScript(bytes, key: key) }
            }, decryptBlock: { bytes, magic in
                try autoreleasepool { try GPArchive.decryptGodot4(bytes, key: key, magic: magic) }
            })
        }
        return try PCKInspector.inspect(pack)
    }
    static func recover(executable: URL, pack: URL) throws -> (PackInfo, Data?) {
        do { return (try PCKInspector.inspect(pack), nil) }
        catch let error as PackError {
            guard error.recoveryMajor != nil else { throw error }
        }
        let keys = try GPArchive.candidateKeys(executable.path)
        for key in keys {
            do {
                let info = try inspect(pack, key: key)
                if info.needsKey { return (info, key) }
            } catch let error as PackError {
                if case .unsupportedRuntime(let reason) = error {
                    throw PackError.unsupportedRuntime("The original EXE key unlocked the pack, but \(reason)")
                }
            } catch { /* A different candidate may match. */ }
        }
        throw PackError.invalid("No matching script key found. Choose the EXE and PCK from the same original download. Only recognized Godot 3/4 Windows x64 runtime layouts are supported.")
    }
}
