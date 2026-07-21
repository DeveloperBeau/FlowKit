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

/// A background actor that owns and mutates an observable, to exercise the
/// non-main-actor observation path. Observation and mutation share this actor,
/// so no change is missed.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
actor ObservableHost {
    let object = TestObservable()

    func makeCountFlow() -> Flow<Int> {
        Flow(observing: object, \.count)
    }

    func setCount(_ value: Int) {
        object.count = value
    }
}

@MainActor
@Suite("Flow(observing:) on the main actor", .enabled(if: isObservationSupported))
struct FlowObservingMainActorTests {
    @Test("emits initial value on subscribe")
    func emitsInitial() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()
        obj.count = 42

        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue(42)
            await tester.cancelAndIgnoreRemaining()
        }
    }

    @Test("emits on value change")
    func emitsOnChange() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()

        // The flow is constructed on the main actor (#isolation), so it observes
        // there. `test`'s block is not main-isolated, so mutate on the main actor
        // explicitly — the contract is that mutation and observation share an
        // actor, which is how SwiftUI code drives an @Observable anyway.
        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue(0) // initial

            await MainActor.run { obj.count = 7 }
            try await tester.expectValue(7)

            await MainActor.run { obj.count = 100 }
            try await tester.expectValue(100)

            await tester.cancelAndIgnoreRemaining()
        }
    }

    @Test("deduplicates equal values")
    func dedup() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let obj = TestObservable()

        let flow: Flow<Int> = Flow(observing: obj, \.count)
        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue(0)
            await MainActor.run { obj.count = 0 } // equal, no emission
            await tester.expectNoValue(within: .milliseconds(100))
            await MainActor.run { obj.count = 1 }
            try await tester.expectValue(1)
            await tester.cancelAndIgnoreRemaining()
        }
    }
}

@Suite("Flow(observing:) on a background actor", .enabled(if: isObservationSupported))
struct FlowObservingBackgroundActorTests {
    @Test("emits changes made on the owning actor")
    func emitsOnChange() async throws {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let host = ObservableHost()
        let flow = await host.makeCountFlow()

        try await flow.test(timeout: .seconds(15)) { tester in
            try await tester.expectValue(0)

            await host.setCount(7)
            try await tester.expectValue(7)

            await host.setCount(100)
            try await tester.expectValue(100)

            await tester.cancelAndIgnoreRemaining()
        }
    }
}
#endif
