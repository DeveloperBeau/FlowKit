#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import Testing
import AppKit
import FlowCore
import FlowHotStreams
@testable import FlowUIKitBridge

@Suite("AppKit bridge")
@MainActor
struct AppKitBridgeTests {
    @Test("NSViewController.flowScope returns same instance on repeated access")
    func vcFlowScopeIdentity() {
        let vc = NSViewController()
        let scope1 = vc.flowScope
        let scope2 = vc.flowScope
        #expect(scope1 === scope2)
    }

    @Test("NSWindowController.flowScope returns same instance")
    func wcFlowScopeIdentity() {
        let wc = NSWindowController()
        let scope1 = wc.flowScope
        let scope2 = wc.flowScope
        #expect(scope1 === scope2)
    }

    @Test("NSViewController.collect with StateFlow works")
    func vcCollectStateFlow() async {
        let vc = NSViewController()
        let state = MutableStateFlow(0)
        vc.collect(state) { _ in }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(vc.flowScope.activeTaskCount >= 1)
        vc.flowScope.cancel()
    }

    @Test("NSViewController.collect with Flow works")
    func vcCollectFlow() async {
        let vc = NSViewController()
        let flow = Flow(of: 1, 2, 3)
        vc.collect(flow) { _ in }
        try? await Task.sleep(nanoseconds: 30_000_000)
        vc.flowScope.cancel()
    }
}
#endif
