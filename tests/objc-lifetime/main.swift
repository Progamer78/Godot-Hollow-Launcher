import Foundation
import ObjectiveC

final class LegitimateCleanup: NSObject {
    static var destroyed = 0
    deinit { LegitimateCleanup.destroyed += 1 }
}

// Run the exact simulator audit on macOS first: a normal Swift destructor is
// permitted, but a class defining a release callback is still rejected.
weak var remaining: LegitimateCleanup?
autoreleasepool {
    let object = LegitimateCleanup()
    remaining = object
    precondition(unsafeLifetimeSelectors(LegitimateCleanup.self).isEmpty,
                 "Compiler-generated dealloc must be permitted")
    var count: UInt32 = 0
    let methods = class_copyMethodList(LegitimateCleanup.self, &count)
    defer { free(methods) }
    let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods![$0])) }
    precondition(names.contains("dealloc"), "Fixture must actually contain the generated destructor")
}
precondition(remaining == nil && LegitimateCleanup.destroyed == 1, "Normal Swift cleanup must execute")

let unsafeClass = objc_allocateClassPair(NSObject.self, "GPUnsafeReleaseAuditFixture", 0)!
let callback: @convention(c) (AnyObject, Selector) -> Void = { _, _ in }
precondition(class_addMethod(unsafeClass, NSSelectorFromString("release"), unsafeBitCast(callback, to: IMP.self), "v@:"))
objc_registerClassPair(unsafeClass)
// Never instantiate this unsafe class or call its deliberately bad method.
precondition(unsafeLifetimeSelectors(unsafeClass) == ["release"], "The original callback collision must still be caught")
objc_disposeClassPair(unsafeClass)
print("Objective-C lifetime audit: generated Swift dealloc accepted, conflicting release rejected")
