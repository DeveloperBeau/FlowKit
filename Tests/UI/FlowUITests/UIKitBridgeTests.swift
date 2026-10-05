#if canImport(UIKit) && !os(watchOS)
import Testing
import UIKit
import FlowCore
import FlowHotStreams
@testable import FlowUIKitBridge

@Suite("UIKit bridge")
@MainActor
struct UIKitBridgeTests {
    @Test("flowScope returns the same instance on repeated access")
    func flowScopeIdentity() {
        let vc = UIViewController()
        let scope1 = vc.flowScope
        let scope2 = vc.flowScope
        // Pointer equality. Same FlowScope instance each time.
        #expect(scope1 === scope2)
    }

    @Test("flowScope is cancelled when view controller is deallocated")
    func flowScopeCancelledOnDealloc() async {
        let stateFlow = MutableStateFlow(0)
        weak var weakScope: FlowScope?
        do {
            let vc = UIViewController()
            weakScope = vc.flowScope
            vc.collect(stateFlow) { _ in }
            // vc goes out of scope here, so flowScope should be released
        }
        // Dealloc may propagate after the view controller leaves scope.
        while weakScope != nil { await Task.yield() }
        #expect(weakScope == nil, "FlowScope should be released with the view controller")
    }
}
#endif
