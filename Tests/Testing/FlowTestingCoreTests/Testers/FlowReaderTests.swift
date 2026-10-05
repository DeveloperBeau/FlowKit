import Testing
import Foundation
import FlowCore
import FlowHotStreams
import FlowSharedModels
@testable import FlowTestingCore

private struct Boom: Error, Equatable {}

/// A latch a producer parks on until the test releases it, so a test decides
/// when an emission happens without sleeping.
private actor Gate {
    private var isOpen = false
    private var parked: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { parked = $0 }
    }

    func open() {
        isOpen = true
        parked?.resume()
        parked = nil
    }
}

@Suite("FlowReader")
struct FlowReaderTests {
    @Test("Values arrive in the order the flow emitted them")
    func valuesArriveInOrder() async throws {
        try await Flow(of: 1, 2, 3).probing { probe in
            try await probe.expectValue(1)
            let second = try await probe.awaitValue()
            #expect(second == 2)
            try await probe.expectValue(3)
            try await probe.expectCompletion()
        }
    }

    @Test("A read made before the flow emits waits for the emission")
    func readWaitsForLaterEmission() async throws {
        let gate = Gate()
        let flow = Flow<Int> { collector in
            await gate.wait()
            await collector.emit(7)
        }
        try await flow.probing { probe in
            let pending = Task { try await probe.awaitValue() }
            await gate.open()
            let value = try await pending.value
            #expect(value == 7)
        }
    }

    @Test("A wrong value records a failure")
    func wrongValueFails() async throws {
        try await withKnownIssue {
            try await Flow(of: 1).probing { probe in
                try await probe.expectValue(2)
            }
        }
    }

    @Test("A flow that completes first fails every later read")
    func completionFailsEveryLaterRead() async throws {
        try await withKnownIssue(isIntermittent: false) {
            try await Flow<Int>.empty.probing { probe in
                await #expect(throws: FlowReaderError.flowEnded) { try await probe.awaitValue() }
                await #expect(throws: FlowReaderError.flowEnded) { try await probe.awaitValue() }
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("expected a value but the flow completed") }
        }
    }

    @Test("Values emitted before completion are still read, then completion is remembered")
    func valuesSurviveCompletion() async throws {
        try await Flow(of: 1).probing { probe in
            try await probe.expectValue(1)
            try await probe.expectCompletion()
        }
    }

    @Test("A throwing flow's error is matched, and a mismatch records a failure")
    func errorMatchedAndMismatched() async throws {
        try await ThrowingFlow<Int> { _ in throw Boom() }.probing { probe in
            try await probe.expectError("boom") { $0 is Boom }
        }
        try await withKnownIssue {
            try await ThrowingFlow<Int> { _ in throw Boom() }.probing { probe in
                try await probe.expectError("never") { _ in false }
            }
        }
    }

    @Test("awaitValue on a failed flow records the failure and keeps failing")
    func awaitValueAfterFailure() async throws {
        try await withKnownIssue(isIntermittent: false) {
            try await ThrowingFlow<Int> { _ in throw Boom() }.probing { probe in
                await #expect(throws: FlowReaderError.flowEnded) { try await probe.awaitValue() }
                await #expect(throws: FlowReaderError.flowEnded) { try await probe.awaitValue() }
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("expected a value but the flow failed") }
        }
    }

    @Test("expectError rejects a value and a completion")
    func expectErrorRejectsEverythingElse() async throws {
        try await withKnownIssue {
            try? await Flow(of: 1).probing { probe in
                try await probe.expectError("any") { _ in true }
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("but received 1") }
        }
        try await withKnownIssue {
            try? await Flow<Int>.empty.probing { probe in
                try await probe.expectError("any") { _ in true }
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("but the flow completed") }
        }
    }

    @Test("expectCompletion rejects a value and a failure")
    func expectCompletionRejectsEverythingElse() async throws {
        try await withKnownIssue {
            try? await Flow(of: 5).probing { probe in
                try await probe.expectCompletion()
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("expected completion but received value 5") }
        }
        try await withKnownIssue {
            try? await ThrowingFlow<Int> { _ in throw Boom() }.probing { probe in
                try await probe.expectCompletion()
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("expected completion but the flow failed") }
        }
    }

    @Test("Collection is cancelled when the block ends")
    func collectionCancelledOnBlockExit() async throws {
        let cancelled = Gate()
        let started = Gate()
        let flow = Flow<Int> { collector in
            await collector.emit(1)
            await started.open()
            do { try await Task.sleep(for: .seconds(3600)) } catch { await cancelled.open() }
        }
        try await flow.probing { probe in
            try await probe.expectValue(1)
            await started.wait()
        }
        await cancelled.wait()
    }

    @Test("A sentinel proves no other value arrived before it")
    func sentinelPattern() async throws {
        let gate = Gate()
        let flow = Flow<Int> { collector in
            await collector.emit(1)
            await gate.wait()
            await collector.emit(-1)
        }
        try await flow.probing { probe in
            try await probe.expectValue(1)
            await gate.open()
            try await probe.expectNextValue(-1)
        }
    }

    @Test("A sentinel read fails naming the value that arrived first")
    func sentinelFailsWhenAnotherValueArrives() async throws {
        try await withKnownIssue {
            try await Flow(of: 9, -1).probing { probe in
                try await probe.expectNextValue(-1)
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("expected -1 next but 9 arrived first") }
        }
    }

    @Test("cancelAndIgnoreRemaining drops unread values")
    func cancelAndIgnoreRemainingDrops() async throws {
        let emitted = Gate()
        let flow = Flow<Int> { collector in
            await collector.emit(1)
            await collector.emit(2)
            await emitted.open()
        }
        try await flow.probing { probe in
            await emitted.wait()
            try await probe.expectValue(1)
            await probe.cancelAndIgnoreRemaining()
            try await probe.expectCompletion()
        }
    }

    @Test("A hot shared flow is read once a subscriber is attached")
    func hotSharedFlow() async throws {
        let shared = MutableSharedFlow<Int>()
        try await shared.asFlow().probing { probe in
            while await shared.subscriptionCount < 1 { await Task.yield() }
            await shared.emit(10)
            await shared.emit(11)
            try await probe.expectValue(10)
            try await probe.expectValue(11)
        }
    }
}
