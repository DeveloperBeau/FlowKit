import Testing
import Flow
import FlowTestSupport
import FlowRecording

private struct BoomError: Error, Equatable {}

@Suite("FlowRecorder")
struct FlowRecorderTests {
    // MARK: - Recording

    @Test("Records the values of a Flow in emission order and finishes when it completes")
    func recordsFlowInOrder() async throws {
        let recorder = FlowRecorder(Flow(of: 3, 1, 2))
        let recorded = try await bounded("wait for the flow to complete") {
            await recorder.values(atLeast: .max)
        }
        #expect(recorded == [3, 1, 2])
        #expect(recorder.values == [3, 1, 2])
        #expect(recorder.isFinished)
        #expect(recorder.failure == nil)
    }

    @Test("Records the values of a ThrowingFlow in emission order and finishes without a failure")
    func recordsThrowingFlowInOrder() async throws {
        let recorder = FlowRecorder(ThrowingFlow(of: "b", "a", "c"))
        let recorded = try await bounded("wait for the throwing flow to complete") {
            await recorder.values(atLeast: .max)
        }
        #expect(recorded == ["b", "a", "c"])
        #expect(recorder.values == ["b", "a", "c"])
        #expect(recorder.isFinished)
        #expect(recorder.failure == nil)
    }

    @Test("An empty flow finishes with no values")
    func emptyFlowFinishesWithNoValues() async throws {
        let recorder = FlowRecorder(Flow<Int>.empty)
        let recorded = try await bounded("wait for the empty flow to complete") {
            await recorder.values(atLeast: 1)
        }
        #expect(recorded == [])
        #expect(recorder.isFinished)
    }

    @Test("Ten thousand values are recorded in order")
    func recordsAHugeFlowInOrder() async throws {
        let recorder = FlowRecorder(Flow(0..<10_000))
        let recorded = try await bounded("wait for ten thousand values") {
            await recorder.values(atLeast: 10_000)
        }
        #expect(recorded == Array(0..<10_000))
    }

    // MARK: - values(atLeast:)

    @Test("values(atLeast:) stays suspended below the count and returns when the count is reached")
    func waitReturnsWhenCountIsReached() async throws {
        let source = MutableSharedFlow<Int>()
        let recorder = FlowRecorder(source.asFlow())
        try await bounded("wait for the recorder to subscribe") {
            try await source.waitForSubscribers(1)
        }
        let returned = Signal()
        let waiter = Task {
            let values = await recorder.values(atLeast: 2)
            returned.fire()
            return values
        }

        await source.emit(10)
        let afterOne = try await bounded("wait for the first value") {
            await recorder.values(atLeast: 1)
        }
        #expect(afterOne == [10])
        #expect(await !returned.firesWithinHops(), "returned with one value when two were asked for")

        await source.emit(20)
        let recorded = try await bounded("wait for the second value") { await waiter.value }
        #expect(recorded == [10, 20])
        #expect(!recorder.isFinished)
        #expect(recorder.failure == nil)
        recorder.cancel()
    }

    @Test("values(atLeast:) returns at once when the count is already recorded")
    func waitReturnsAtOnceWhenAlreadySatisfied() async throws {
        let source = MutableSharedFlow<Int>(replay: 2)
        await source.emit(1)
        await source.emit(2)
        let recorder = FlowRecorder(source.asFlow())
        let first = try await bounded("wait for the replayed values") {
            await recorder.values(atLeast: 2)
        }
        let second = try await bounded("wait for one value when two are recorded") {
            await recorder.values(atLeast: 1)
        }
        #expect(first == [1, 2])
        #expect(second == [1, 2])
        recorder.cancel()
    }

    @Test("values(atLeast:) returns what it has when the flow completes early")
    func waitReturnsWhatItHasOnEarlyCompletion() async throws {
        let recorder = FlowRecorder(Flow(of: 1, 2))
        let recorded = try await bounded("wait for five values from a flow of two") {
            await recorder.values(atLeast: 5)
        }
        #expect(recorded == [1, 2])
        #expect(recorder.isFinished)
    }

    @Test("A count of zero or less returns at once on a flow that never emits")
    func nonPositiveCountReturnsAtOnce() async throws {
        let recorder = FlowRecorder(Flow<Int> { _ in await parkUntilCancelled() })
        let zero = try await bounded("wait for zero values") { await recorder.values(atLeast: 0) }
        let negative = try await bounded("wait for a negative count") {
            await recorder.values(atLeast: -3)
        }
        #expect(zero == [])
        #expect(negative == [])
        #expect(!recorder.isFinished)
        recorder.cancel()
    }

    @Test("Cancelling the waiting task returns what was recorded and leaves the recorder running")
    func cancelledWaiterReturnsWhatItHas() async throws {
        let source = MutableSharedFlow<Int>()
        let recorder = FlowRecorder(source.asFlow())
        try await bounded("wait for the recorder to subscribe") {
            try await source.waitForSubscribers(1)
        }
        await source.emit(1)
        let started = Signal()
        let waiter = Task {
            started.fire()
            return await recorder.values(atLeast: 5)
        }
        await started.wait()
        waiter.cancel()
        let partial = try await bounded("wait for the cancelled waiter") { await waiter.value }
        #expect(partial == [1])
        #expect(!recorder.isFinished)

        await source.emit(2)
        let later = try await bounded("wait for a value after a waiter was cancelled") {
            await recorder.values(atLeast: 2)
        }
        #expect(later == [1, 2])
        recorder.cancel()
    }

    @Test("A task that is already cancelled returns at once with what was recorded")
    func alreadyCancelledWaiterReturnsAtOnce() async throws {
        let recorder = FlowRecorder(Flow<Int> { _ in await parkUntilCancelled() })
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await recorder.values(atLeast: 1)
        }
        let values = try await bounded("wait for the already cancelled waiter") { await waiter.value }
        #expect(values == [])
        #expect(!recorder.isFinished)
        recorder.cancel()
    }

    @Test("Waiters with different counts each resume at their own count")
    func concurrentWaitersResumeAtTheirOwnCount() async throws {
        let source = MutableSharedFlow<Int>()
        let recorder = FlowRecorder(source.asFlow())
        try await bounded("wait for the recorder to subscribe") {
            try await source.waitForSubscribers(1)
        }
        let waiters = (1...8).map { count in
            Task { await recorder.values(atLeast: count) }
        }
        for value in 1...8 { await source.emit(value) }
        for (index, waiter) in waiters.enumerated() {
            let values = try await bounded("wait for waiter \(index + 1)") { await waiter.value }
            #expect(values.count >= index + 1)
            #expect(values == Array(1...values.count))
        }
        recorder.cancel()
    }

    // MARK: - Failure

    @Test("A throwing flow's error is exposed through failure and the recorder is finished")
    func failureIsExposed() async throws {
        let recorder = FlowRecorder(ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BoomError()
        })
        let recorded = try await bounded("wait for the throwing flow to fail") {
            await recorder.values(atLeast: 3)
        }
        #expect(recorded == [1])
        #expect(recorder.isFinished)
        #expect(recorder.failure as? BoomError == BoomError())
    }

    @Test("failure stays nil while a throwing flow is still open")
    func failureIsNilWhileOpen() async throws {
        let recorder = FlowRecorder(ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            await parkUntilCancelled()
        })
        let recorded = try await bounded("wait for the first value") {
            await recorder.values(atLeast: 1)
        }
        #expect(recorded == [1])
        #expect(!recorder.isFinished)
        #expect(recorder.failure == nil)
        recorder.cancel()
    }

    // MARK: - Teardown

    @Test("cancel() stops the upstream once, finishes the recorder, and resumes a waiter")
    func cancelStopsTheUpstream() async throws {
        let teardowns = Recorder<Void>()
        let recorder = FlowRecorder(Flow<Int> { collector in
            await collector.emit(1)
            await parkUntilCancelled()
            teardowns.record(())
        })
        _ = try await bounded("wait for the first value") { await recorder.values(atLeast: 1) }
        let started = Signal()
        let waiter = Task {
            started.fire()
            return await recorder.values(atLeast: 2)
        }
        await started.wait()
        #expect(teardowns.count == 0)

        recorder.cancel()
        recorder.cancel()

        #expect(recorder.isFinished)
        let pending = try await bounded("wait for the waiter after cancel()") { await waiter.value }
        #expect(pending == [1])
        try await bounded("wait for the upstream to stop after cancel()") {
            await teardowns.wait(atLeast: 1)
        }
        #expect(teardowns.count == 1)
    }

    @Test("Releasing the recorder stops the upstream once")
    func deinitStopsTheUpstream() async throws {
        let teardowns = Recorder<Void>()
        var recorder: FlowRecorder<Int>? = FlowRecorder(Flow<Int> { collector in
            await collector.emit(1)
            await parkUntilCancelled()
            teardowns.record(())
        })
        let held = try #require(recorder)
        _ = try await bounded("wait for the first value") { await held.values(atLeast: 1) }
        #expect(teardowns.count == 0)

        _ = consume held
        recorder = nil

        try await bounded("wait for the upstream to stop after release") {
            await teardowns.wait(atLeast: 1)
        }
        #expect(teardowns.count == 1)
    }

    @Test("A value the upstream sends after cancel() is not recorded")
    func valuesAfterCancelAreNotRecorded() async throws {
        let ended = Signal()
        let recorder = FlowRecorder(Flow<Int> { collector in
            await collector.emit(1)
            await parkUntilCancelled()
            await collector.emit(2)
            ended.fire()
        })
        _ = try await bounded("wait for the first value") { await recorder.values(atLeast: 1) }
        recorder.cancel()
        try await bounded("wait for the upstream to end") { await ended.wait() }
        #expect(recorder.values == [1])
    }

    @Test("An error the upstream throws after cancel() is not reported as a failure")
    func errorAfterCancelIsNotAFailure() async throws {
        let ended = Signal()
        let recorder = FlowRecorder(ThrowingFlow<Int> { collector in
            defer { ended.fire() }
            try await collector.emit(1)
            await parkUntilCancelled()
            throw BoomError()
        })
        _ = try await bounded("wait for the first value") { await recorder.values(atLeast: 1) }
        recorder.cancel()
        try await bounded("wait for the upstream to end") { await ended.wait() }
        // Give the collection task room to hand the late error to the recorder.
        for _ in 0..<100 { await Task.yield() }
        #expect(recorder.isFinished)
        #expect(recorder.failure == nil)
    }

    // MARK: - Hot flows

    @Test("A hot flow sees its subscriber once the recorder is created")
    func hotFlowSeesTheSubscriber() async throws {
        let source = MutableSharedFlow<String>()
        let recorder = FlowRecorder(source.asFlow())
        try await bounded("wait for the recorder to subscribe") {
            try await source.waitForSubscribers(1)
        }
        await source.emit("off")
        await source.emit("on")
        let recorded = try await bounded("wait for two values from the hot flow") {
            await recorder.values(atLeast: 2)
        }
        #expect(recorded == ["off", "on"])

        recorder.cancel()
        try await bounded("wait for the recorder to unsubscribe") {
            try await source.waitForSubscribers(atMost: 0)
        }
    }

    @Test("A recorder is read from a non-test isolation without a hop")
    @MainActor
    func readsFromTheMainActor() async throws {
        let recorder = FlowRecorder(Flow(of: 1))
        let recorded = try await bounded("wait for one value") { await recorder.values(atLeast: 1) }
        #expect(recorded == [1])
        #expect(recorder.values == [1])
    }
}
