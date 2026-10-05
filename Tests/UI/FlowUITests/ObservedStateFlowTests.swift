#if canImport(SwiftUI) && canImport(Observation)
import Testing
import SwiftUI
import Foundation
import FlowCore
import FlowHotStreams
import FlowTesting
import FlowTestSupport
@testable import FlowSwiftUI

private let isSupported = {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) {
        return true
    }
    return false
}()

/// Suspends until `read()` equals `expected`, woken by Observation rather than
/// a clock. Observation tracking registers synchronously on the main actor in
/// the same step that read the stale value, so a change cannot slip between
/// the check and the registration, and a stalled process only delays the wake.
/// A value that moves somewhere other than `expected` fails the read by name
/// instead of waiting forever. A source that never delivers at all parks until
/// the test is cancelled: only a clock could say "nothing is coming".
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
@MainActor
private func awaitValue<Value: Equatable>(
    _ expected: Value,
    of read: @MainActor () -> Value,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let start = read()
    while true {
        let current = read()
        if current == expected { return }
        if current != start {
            Issue.record(
                "value became \(current) while waiting for \(expected)",
                sourceLocation: sourceLocation
            )
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking { _ = read() } onChange: { continuation.resume() }
        }
    }
}

/// Blocks the main actor, as a stalled process would, so no queued job runs.
@MainActor
private func stallMainActor(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
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
        await awaitValue(1, of: { observed.value })
        #expect(observed.value == 1)

        source.send(99)
        await awaitValue(99, of: { observed.value })
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
        await awaitValue(1, of: { observed.value })
        observed.stop()
    }

    @Test("stop cancels collection")
    func stopCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(1)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        // Confirm collection is actually running before stopping it.
        await awaitValue(1, of: { observed.value })
        observed.stop()

        source.send(777) // applied synchronously; delivery to observers is async
        await settle()
        #expect(observed.value == 1, "a stopped observer must not apply new emissions")
    }

    @Test("deduplicates equal values")
    func deduplicates() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(5)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        await awaitValue(5, of: { observed.value })
        #expect(observed.value == 5)

        source.send(5) // equal, no update
        source.send(6) // sentinel: once it lands, the equal send had its chance
        await awaitValue(6, of: { observed.value })
        #expect(observed.value == 6)
        observed.stop()
    }

    @Test("a value that moves somewhere unexpected fails the wait by name")
    func wrongValueFailsByName() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(0)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        source.send(7)
        await withKnownIssue {
            await awaitValue(8, of: { observed.value })
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("value became 7 while waiting for 8") }
        }
        observed.stop()
    }

    @Test("a main actor stall delays the wait without failing it")
    func stallDoesNotFailTheWait() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let source = MutableStateFlow(3)
        let observed = ObservedStateFlow(source, initialValue: 0)
        observed.start()
        stallMainActor(seconds: 1.5)
        await awaitValue(3, of: { observed.value })
        #expect(observed.value == 3)
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
        source.send(10)
        await awaitValue(10, of: { observed.value })
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
        source.send(20)
        await awaitValue(20, of: { observed.value })
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
        source.send(42)
        await awaitValue(42, of: { wrapper.wrappedValue })
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
        await awaitValue(5, of: { wrapper.wrappedValue })
        #expect(wrapper.wrappedValue == 5)
    }
}

@Suite("ObservedStateFlow deinit", .enabled(if: isSupported))
@MainActor
struct ObservedStateFlowDeinitTests {
    @Test("deinit cancels collection task")
    func deinitCancels() async {
        guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }
        let probe = CancellationProbe()
        do {
            let observed = ObservedStateFlow(probe, initialValue: 0)
            observed.start()
            await probe.started.wait()
            #expect(probe.started.hasFired)
            // observed goes out of scope here, so releasing it must cancel the task
        }
        await probe.cancelled.wait()
        #expect(probe.cancelled.hasFired)
    }
}

/// A state flow whose collection parks until cancelled, signalling when it
/// starts and when it is cancelled.
private final class CancellationProbe: StateFlow, Sendable {
    let started = Signal()
    let cancelled = Signal()
    var value: Int { 0 }

    func asFlow() -> Flow<Int> {
        Flow { _ in
            self.started.fire()
            await withTaskCancellationHandler {
                await parkUntilCancelled()
            } onCancel: {
                self.cancelled.fire()
            }
        }
    }
}
#endif
