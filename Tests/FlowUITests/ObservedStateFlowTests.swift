#if canImport(SwiftUI) && canImport(Observation)
import Testing
import SwiftUI
import FlowCore
import FlowHotStreams
import FlowTesting
@testable import FlowSwiftUI

private let isSupported = {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) {
        return true
    }
    return false
}()

/// Spins until `condition` holds, yielding between checks. Observation updates
/// hop through the collection task and back to the main actor, so a fixed sleep
/// is a race — on a slow simulator the update lands after it. This converges
/// once the update arrives (and hangs into a visible timeout if it never does,
/// rather than passing flakily).
@MainActor
private func poll(until condition: () -> Bool) async {
    while !condition() { await Task.yield() }
}

/// Gives a stopped or deduplicated observer every scheduling chance to (wrongly)
/// apply an update, so a negative assertion is not merely racing the update.
@MainActor
private func settle() async {
    for _ in 0..<100 { await Task.yield() }
}

@Suite("ObservedStateFlow", .enabled(if: isSupported))
@MainActor
struct ObservedStateFlowTests {
    @Test("initial value is exposed before start")
    func initialValue() {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(source, initialValue: 42)
        #expect(observed.value == 42)
    }

    @Test("start begins collection and updates value")
    func startCollects() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(1)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        await poll { observed.value == 1 }
        #expect(observed.value == 1)

        await source.send(99)
        await poll { observed.value == 99 }
        #expect(observed.value == 99)
        observed.stop()
    }

    @Test("start is idempotent")
    func startIdempotent() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(1)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        observed.start() // no-op second call
        // A second start must not double-collect or crash; wait for the single
        // collection to land, then tear down.
        await poll { observed.value == 1 }
        observed.stop()
    }

    @Test("stop cancels collection")
    func stopCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(1)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        // Confirm collection is actually running before stopping it.
        await poll { observed.value == 1 }
        observed.stop()

        await source.send(777)
        _ = await source.value // ensure the send is fully processed
        await settle()
        #expect(observed.value == 1, "a stopped observer must not apply new emissions")
    }

    @Test("deduplicates equal values")
    func deduplicates() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(5)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        await poll { observed.value == 5 }
        #expect(observed.value == 5)

        await source.send(5) // equal, no update
        _ = await source.value
        await settle()
        #expect(observed.value == 5)
        observed.stop()
    }

    @Test("animated update policy applies")
    func animatedPolicy() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(
            source,
            initialValue: 0,
            updatePolicy: .animated(.default)
        )
        observed.start()
        await source.send(10)
        await poll { observed.value == 10 }
        #expect(observed.value == 10)
        observed.stop()
    }

    @Test("transaction update policy applies")
    func transactionPolicy() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(
            source,
            initialValue: 0,
            updatePolicy: .transaction { Transaction(animation: .default) }
        )
        observed.start()
        await source.send(20)
        await poll { observed.value == 20 }
        #expect(observed.value == 20)
        observed.stop()
    }
}

@Suite("@CollectedState", .enabled(if: isSupported))
@MainActor
struct CollectedStateTests {
    @Test("CollectedState exposes initial value")
    func initialValue() {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(100)
        let wrapper = CollectedState(wrappedValue: 0, source)
        #expect(wrapper.wrappedValue == 0)
    }

    @Test("CollectedState with animation is constructible")
    func withAnimation() {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow("hello")
        let wrapper = CollectedState(wrappedValue: "", source, animation: .default)
        #expect(wrapper.wrappedValue == "")
    }

    @Test("update() starts collection")
    func updateStarts() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let wrapper = CollectedState(wrappedValue: 0, source)
        wrapper.update() // simulates SwiftUI calling update during view update
        await source.send(42)
        await poll { wrapper.wrappedValue == 42 }
        #expect(wrapper.wrappedValue == 42)
    }

    @Test("update() is idempotent across repeated calls")
    func updateIdempotent() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(5)
        let wrapper = CollectedState(wrappedValue: 0, source)
        wrapper.update()
        wrapper.update()
        wrapper.update()
        await poll { wrapper.wrappedValue == 5 }
        #expect(wrapper.wrappedValue == 5)
    }
}

@Suite("ObservedStateFlow deinit", .enabled(if: isSupported))
@MainActor
struct ObservedStateFlowDeinitTests {
    @Test("deinit cancels collection task")
    func deinitCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(1)
        do {
            let observed = ObservedStateFlow(source, initialValue: 0)
            observed.start()
            await poll { observed.value == 1 }
            // observed goes out of scope here, so isolated deinit fires
        }
        await settle()
        // No assertion. Just verify the deinit path runs without crash.
    }
}
#endif
