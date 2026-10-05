import Testing
import FlowCore
import FlowTestSupport
@testable import FlowTestingCore

@Suite("FlowProbe waitForValue")
struct FlowProbeTests {
    @Test("Returns at once when the latest value already satisfies the predicate")
    func returnsWhenAlreadySatisfied() async throws {
        let probe = FlowProbe<Int>()
        await probe.record(3)
        try await probe.waitForValue { $0 == 3 }
    }

    @Test("Suspends until a recorded value satisfies the predicate")
    func waitsForAMatchingValue() async throws {
        let probe = FlowProbe<Int>()
        let resumed = Signal()
        let waiter = Task {
            try await probe.waitForValue { $0 == 3 }
            resumed.fire()
        }

        await probe.record(1)
        await probe.record(2)
        // Let the waiter see the non-matching values before the matching one.
        for _ in 0..<20 { await Task.yield() }
        #expect(!resumed.hasFired, "resumed on a value that does not match")

        await probe.record(3)
        try await waiter.value
        #expect(resumed.hasFired)
    }

    @Test("Resumes every waiter whose predicate a value satisfies")
    func resumesAllMatchingWaiters() async throws {
        let probe = FlowProbe<String>()
        let first = Task { try await probe.waitForValue { $0 == "a" } }
        let second = Task { try await probe.waitForValue { $0.hasPrefix("a") } }
        let third = Task { try await probe.waitForValue { $0 == "b" } }
        for _ in 0..<20 { await Task.yield() }

        await probe.record("a")
        try await first.value
        try await second.value

        await probe.record("b")
        try await third.value
    }

    @Test("Cancelling the waiter throws CancellationError")
    func cancellationThrows() async throws {
        let probe = FlowProbe<Int>()
        let started = Signal()
        let waiter = Task {
            started.fire()
            try await probe.waitForValue { $0 == 1 }
        }
        await started.wait()
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }

        // A value recorded afterwards must not resume the cancelled waiter again.
        await probe.record(1)
        try await probe.waitForValue { $0 == 1 }
    }

    @Test("An already-cancelled task throws instead of waiting")
    func alreadyCancelledThrows() async {
        let probe = FlowProbe<Int>()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await probe.waitForValue { _ in false }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("tap(after:) records each value once it has been delivered downstream")
    func tapsThroughAnOperator() async throws {
        let probe = FlowProbe<Int>()
        let flow = Flow(of: 1, 2, 3).tap(after: probe)
        let reader = Task { await flow.collect { _ in } }
        try await probe.waitForValue { $0 == 3 }
        await reader.value
        #expect(await probe.last == 3)
    }
}
