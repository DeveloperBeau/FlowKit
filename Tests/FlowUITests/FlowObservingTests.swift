#if canImport(Observation)
import Testing
import Observation
import FlowCore
import FlowTesting
@testable import FlowSwiftUI

// Under `NonisolatedNonsendingByDefault` (Swift 6.3), KeyPath is not inferred as
// Sendable. Flow(observing:) requires KP: KeyPath<Root, Element> & Sendable.
// This retroactive conformance is safe in a test module: key paths are value-
// semantic, immutable after creation, and safe to share across concurrency domains.
extension KeyPath: @retroactive @unchecked Sendable {}

private let isObservationSupported = {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) {
        return true
    }
    return false
}()

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
@Observable
final class TestObservable: @unchecked Sendable {
    var count: Int = 0
    var name: String = "initial"
}

@Suite("Flow(observing:)", .enabled(if: isObservationSupported))
struct FlowObservingTests {
    @Test("emits initial value on subscribe")
    func emitsInitial() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()
        obj.count = 42

        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(2)) { tester in
            try await tester.expectValue(42)
            await tester.cancelAndIgnoreRemaining()
        }
    }

    @Test("emits on value change")
    func emitsOnChange() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()

        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(2)) { tester in
            try await tester.expectValue(0) // initial

            obj.count = 7
            try await tester.expectValue(7)

            obj.count = 100
            try await tester.expectValue(100)

            await tester.cancelAndIgnoreRemaining()
        }
    }

    @Test("deduplicates equal values")
    func dedup() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()

        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(2)) { tester in
            try await tester.expectValue(0)
            obj.count = 0 // equal, no emission
            await tester.expectNoValue(within: .milliseconds(100))
            obj.count = 1
            try await tester.expectValue(1)
            await tester.cancelAndIgnoreRemaining()
        }
    }
}
#endif
