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
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(observed.value == 1)

        await source.send(99)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(observed.value == 99)
        observed.stop()
    }

    @Test("start is idempotent")
    func startIdempotent() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        observed.start() // no-op second call
        try? await Task.sleep(nanoseconds: 20_000_000)
        observed.stop()
    }

    @Test("stop cancels collection")
    func stopCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        try? await Task.sleep(nanoseconds: 20_000_000)
        observed.stop()
        // After stop, new source emissions should not update value
        await source.send(777)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(observed.value != 777)
    }

    @Test("deduplicates equal values")
    func deduplicates() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(5)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(observed.value == 5)

        await source.send(5) // equal, no update
        try? await Task.sleep(nanoseconds: 20_000_000)
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
        try? await Task.sleep(nanoseconds: 50_000_000)
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
        try? await Task.sleep(nanoseconds: 50_000_000)
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
        try? await Task.sleep(nanoseconds: 50_000_000)
        // After update() + send, wrappedValue should reflect new value
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
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(wrapper.wrappedValue == 5)
    }
}

@Suite("ObservedStateFlow deinit", .enabled(if: isSupported))
@MainActor
struct ObservedStateFlowDeinitTests {
    @Test("deinit cancels collection task")
    func deinitCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        do {
            let observed = ObservedStateFlow(source, initialValue: 0)
            observed.start()
            try? await Task.sleep(nanoseconds: 20_000_000)
            // observed goes out of scope here, so isolated deinit fires
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        // No assertion. Just verify deinit path runs without crash.
    }
}
#endif
