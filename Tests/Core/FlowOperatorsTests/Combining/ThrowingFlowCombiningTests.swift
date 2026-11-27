import Testing
import FlowCore
import FlowHotStreams
import FlowTesting
import FlowTestSupport
@testable import FlowOperators

@Suite("ThrowingFlow combining operators")
struct ThrowingFlowCombiningTests {
    // MARK: - zip

    @Test("ThrowingFlow.zip pairs values positionally")
    func zipPairs() async throws {
        let flow1 = ThrowingFlow(of: 1, 2, 3)
        let flow2 = ThrowingFlow(of: "a", "b", "c")
        try await flow1.zip(flow2).probing { tester in
            let v1 = try await tester.awaitValue()
            #expect(v1.0 == 1 && v1.1 == "a")
            let v2 = try await tester.awaitValue()
            #expect(v2.0 == 2 && v2.1 == "b")
            let v3 = try await tester.awaitValue()
            #expect(v3.0 == 3 && v3.1 == "c")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.zip propagates errors from either side")
    func zipPropagatesError() async throws {
        struct ZipError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw ZipError()
        }
        let flow2 = ThrowingFlow(of: "a", "b", "c")
        try await flow1.zip(flow2).probing { tester in
            _ = try await tester.awaitValue()
            try await tester.expectError(ZipError())
        }
    }

    // MARK: - combineLatest

    @Test("ThrowingFlow.combineLatest emits latest pairs")
    func combineLatestPairs() async throws {
        let flow1 = ThrowingFlow(of: 1, 2)
        let flow2 = ThrowingFlow(of: 10, 20)
        try await flow1.combineLatest(flow2).probing { tester in
            let first = try await tester.awaitValue()
            #expect(first.0 >= 1 && first.1 >= 10)
        }
    }

    @Test("ThrowingFlow.combineLatest propagates errors")
    func combineLatestPropagatesError() async throws {
        struct CombineError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { _ in throw CombineError() }
        let flow2 = ThrowingFlow(of: 1, 2, 3)
        try await flow1.combineLatest(flow2).probing { tester in
            try await tester.expectError(CombineError())
        }
    }

    // MARK: - merge

    @Test("ThrowingFlow.merge interleaves values")
    func mergeInterleaves() async throws {
        let flow1 = ThrowingFlow(of: 1, 2, 3)
        let flow2 = ThrowingFlow(of: 10, 20, 30)
        try await ThrowingFlow.merge(flow1, flow2).probing { tester in
            var received: [Int] = []
            for _ in 0..<6 {
                received.append(try await tester.awaitValue())
            }
            #expect(Set(received) == Set([1, 2, 3, 10, 20, 30]))
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.merge propagates errors from any flow")
    func mergePropagatesError() async throws {
        struct MergeError: Error, Equatable {}
        let flow1 = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw MergeError()
        }
        let flow2 = ThrowingFlow<Int> { _ in
            // Never emits. Just waits so merge stays alive until error fires.
        }
        try await ThrowingFlow.merge(flow1, flow2).probing { tester in
            _ = try await tester.awaitValue()  // the 1 from flow1
            try await tester.expectError(MergeError())
        }
    }

    private struct MergeBoom: Error, Equatable {}

    /// Parks until the task is cancelled, then runs `onCancel`.
    private static func openSibling(
        started: Signal,
        cancelled: Signal,
        afterCancel: @escaping @Sendable (ThrowingCollector<Int>) async -> Void = { _ in }
    ) -> ThrowingFlow<Int> {
        ThrowingFlow<Int> { out in
            started.fire()
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            for await _ in stream {}  // ends only on cancellation
            continuation.finish()
            cancelled.fire()
            await afterCancel(out)
        }
    }

    /// Collects `flow` in a task. Returns the task, the error it ended with and the values it saw.
    private static func collectInTask(
        _ flow: ThrowingFlow<Int>
    ) -> (task: Task<Void, Never>, ended: Signal, error: Mutex<(any Error)?>, values: Mutex<[Int]>) {
        let ended = Signal()
        let error = Mutex<(any Error)?>(nil)
        let values = Mutex<[Int]>([])
        let task = Task {
            do {
                try await flow.collect { value in values.withLock { $0.append(value) } }
            } catch let thrown {
                error.withLock { $0 = thrown }
            }
            ended.fire()
        }
        return (task, ended, error, values)
    }

    @Test("ThrowingFlow.merge rethrows a failure while a sibling is still open")
    func mergeFailureWithOpenSiblingThrows() async throws {
        let started = Signal()
        let failing = ThrowingFlow<Int> { _ in
            _ = await started.fires(safetyNet: .seconds(5))
            throw MergeBoom()
        }
        let run = Self.collectInTask(
            .merge(failing, Self.openSibling(started: started, cancelled: Signal())))
        defer { run.task.cancel() }
        try #require(await run.ended.fires(safetyNet: .seconds(5)), "merge held the error for the open sibling")
        #expect(run.error.withLock { $0 } as? MergeBoom == MergeBoom())
    }

    @Test("ThrowingFlow.merge cancels an open sibling after a failure")
    func mergeFailureCancelsOpenSibling() async throws {
        let started = Signal()
        let cancelled = Signal()
        let failing = ThrowingFlow<Int> { _ in
            _ = await started.fires(safetyNet: .seconds(5))
            throw MergeBoom()
        }
        let run = Self.collectInTask(
            .merge(failing, Self.openSibling(started: started, cancelled: cancelled)))
        defer { run.task.cancel() }
        try #require(await cancelled.fires(safetyNet: .seconds(5)), "the open sibling was never cancelled")
        try #require(await run.ended.fires(safetyNet: .seconds(5)), "merge never ended")
    }

    @Test("ThrowingFlow.merge delivers nothing after the failure")
    func mergeFailureEmitsNothingAfterError() async throws {
        let started = Signal()
        let failing = ThrowingFlow<Int> { _ in
            _ = await started.fires(safetyNet: .seconds(5))
            throw MergeBoom()
        }
        let sibling = Self.openSibling(started: started, cancelled: Signal()) { out in
            try? await out.emit(99)  // a late value from the cancelled sibling
        }
        let run = Self.collectInTask(.merge(failing, sibling))
        defer { run.task.cancel() }
        try #require(await run.ended.fires(safetyNet: .seconds(5)), "merge never ended")
        #expect(run.values.withLock { $0 }.isEmpty)
    }

    @Test("ThrowingFlow.merge with array completes when all complete")
    func mergeArrayCompletes() async throws {
        let flows: [ThrowingFlow<Int>] = [ThrowingFlow(of: 1), ThrowingFlow(of: 2)]
        try await ThrowingFlow.merge(flows).probing { tester in
            var received: [Int] = []
            for _ in 0..<2 {
                received.append(try await tester.awaitValue())
            }
            #expect(Set(received) == Set([1, 2]))
            try await tester.expectCompletion()
        }
    }
}
