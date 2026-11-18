import Foundation

enum ExecutableImport {
    static func inspect(_ pack: URL, key: Data?, externalFiles: URL? = nil, allowDotnet: Bool = DotnetRuntime.bundled, verified: (() -> Void)? = nil) throws -> PackInfo {
        if let key = key {
            guard key.count == 32 else { throw PackError.invalid("Invalid private script key.") }
            return try PCKInspector.inspect(pack, decryptScript: { bytes in
                let plain = try autoreleasepool { try GPArchive.decryptScript(bytes, key: key) }
                if !plain.isEmpty { verified?() }; return plain
            }, decryptBlock: { bytes, magic in
                let plain = try autoreleasepool { try GPArchive.decryptGodot4(bytes, key: key, magic: magic) }
                if !plain.isEmpty { verified?() }; return plain
            }, allowDotnet: allowDotnet, externalAssembly: GameFiles.externalAssembly(in: externalFiles))
        }
        return try PCKInspector.inspect(pack, allowDotnet: allowDotnet, externalAssembly: GameFiles.externalAssembly(in: externalFiles))
    }
    static func recover(executable: URL, pack: URL, externalFiles: URL? = nil, allowDotnet: Bool = DotnetRuntime.bundled) throws -> (PackInfo, Data?) {
        do { return (try PCKInspector.inspect(pack, allowDotnet: allowDotnet, externalAssembly: GameFiles.externalAssembly(in: externalFiles)), nil) }
        catch let error as PackError {
            guard error.recoveryMajor != nil else { throw error }
        }
        let keys = try GPArchive.candidateKeys(executable.path)
        for key in keys {
            var keyVerified = false
            do {
                let info = try inspect(pack, key: key, externalFiles: externalFiles, allowDotnet: allowDotnet, verified: { keyVerified = true })
                if info.needsKey { return (info, key) }
            } catch let error as PackError {
                if case .unsupportedRuntime(let reason) = error {
                    throw PackError.unsupportedRuntime("The original EXE key unlocked the pack, but \(reason)")
                }
                if keyVerified { throw PackError.unsupportedRuntime("The original EXE key unlocked the pack, but \(error.localizedDescription)") }
            } catch {
                if keyVerified { throw error }
            }
        }
        throw PackError.invalid("No matching script key found. Choose the EXE and PCK from the same original download. Only recognized Godot 3/4 Windows x64 runtime layouts are supported.")
    }
}
