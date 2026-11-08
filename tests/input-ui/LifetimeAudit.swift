import Foundation
import ObjectiveC

func unsafeLifetimeSelectors(_ type: AnyClass) -> [String] {
    var count: UInt32 = 0
    guard let methods = class_copyMethodList(type, &count) else { return [] }
    defer { free(methods) }
    // Swift synthesizes dealloc for a legitimate deinit. That method must be
    // allowed here; the source audit separately rejects hand-written @objc
    // lifetime callbacks. These four selectors must never be custom callbacks.
    let forbidden: Set<String> = ["release", "retain", "autorelease", "retainCount"]
    return (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
        .filter { forbidden.contains($0) }.sorted()
}
