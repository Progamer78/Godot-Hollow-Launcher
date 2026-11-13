import Foundation

let pack = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    _ = try PCKInspector.inspect(pack, allowDotnet: false)
    fatalError("Managed game accepted with its runtime disabled")
} catch let error as PackError {
    guard case .unsupportedRuntime = error else { throw error }
}
let info = try PCKInspector.inspect(pack, allowDotnet: true)
precondition(info.major == 4 && info.requiresDotnet == true)
precondition((info.nativeFiles ?? []).isEmpty, "Managed game assemblies must not require the native-extension fallback switch")
print("HOLLOW_DOTNET_IMPORT_PASS: compiled original game accepted with runtime enabled; rejected with runtime disabled")
