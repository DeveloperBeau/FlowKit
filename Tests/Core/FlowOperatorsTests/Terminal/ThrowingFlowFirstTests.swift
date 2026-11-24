import Testing
import FlowCore
import FlowTesting
import FlowTestSupport
@testable import FlowOperators

@Suite("ThrowingFlow first and first(where:)")
struct ThrowingFlowFirstTests {
    private struct Failure: Error, Equatable {
        let code: Int
    }

    private static let fuzzSeed: UInt64 = 20_261_124

    /// A flow that emits `values`, then stays open until it is cancelled. It
    /// fires `started` once it runs and `tornDown` when the cancellation
    /// arrives, and it rethrows the cancellation error.
    private func openFlow(
        _ values: Int...,
        started: Signal = Signal(),
        tornDown: Signal
    ) -> ThrowingFlow<Int> {
        ThrowingFlow<Int> { collector in
            started.fire()
            for value in values { try await collector.emit(value) }
            do {
                try await Task.sleep(for: .seconds(1 << 40))
            } catch {
                tornDown.fire()
                throw error
            }
        }
    }

    // MARK: - first

    @Test("first returns the first of three values and the upstream ends exactly once")
    func firstReturnsFirstValueAndUpstreamEndsOnce() async throws {
        let endings = Recorder<Int>()
        let flow = ThrowingFlow<Int> { collector in
            defer { endings.record(0) }
            for value in [1, 2, 3] { try await collector.emit(value) }
        }
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == 1)
        #expect(endings.count == 1)
    }

    @Test("first returns the first value of a flow that stays open and tears the producer down")
    func firstOnOpenFlowReturnsAndTearsDown() async throws {
        let tornDown = Signal()
        let flow = openFlow(7, 8, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == 7)
        #expect(tornDown.hasFired)
    }

    @Test("first returns nil for a flow that completes without emitting")
    func firstOnEmptyFlowReturnsNil() async throws {
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await ThrowingFlow<Int>.empty.first()
        }
        #expect(result == nil)
    }

    @Test("first rethrows the same error when the flow throws before it emits")
    func firstRethrowsErrorThrownBeforeFirstValue() async throws {
        let flow = ThrowingFlow<Int> { _ in throw Failure(code: 41) }
        await #expect(throws: Failure(code: 41)) {
            try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        }
    }

    @Test("first returns the value when the flow throws after it emits")
    func firstReturnsValueWhenFlowThrowsAfterEmitting() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(5)
            throw Failure(code: 42)
        }
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == 5)
    }

    @Test("first returns the value when the upstream teardown throws its own error")
    func firstDropsErrorRaisedByTeardown() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(9)
            await parkUntilCancelled()
            throw Failure(code: 43)
        }
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == 9)
    }

    @Test("first keeps a nil element apart from an empty flow")
    func firstReturnsNilElementAsValue() async throws {
        let flow = ThrowingFlow<Int?>(of: nil, 2)
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == .some(nil))
    }

    @Test("first returns from a producer that emits without end")
    func firstOnEndlessProducerReturns() async throws {
        let flow = ThrowingFlow<Int> { collector in
            var next = 0
            while true {
                try Task.checkCancellation()
                try await collector.emit(next)
                next += 1
            }
        }
        let result = try await withThrowingTimeout(.seconds(30)) { try await flow.first() }
        #expect(result == 0)
    }

    // MARK: - first(where:)

    @Test("first(where:) skips values that do not match and returns the first match")
    func firstWhereSkipsNonMatchingValues() async throws {
        let tornDown = Signal()
        let flow = openFlow(1, 2, 3, 4, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { $0 > 2 })
        }
        #expect(result == 3)
        #expect(tornDown.hasFired)
    }

    @Test("first(where:) returns nil when the flow completes without a match")
    func firstWhereWithoutMatchReturnsNil() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { $0 > 3 })
        }
        #expect(result == nil)
    }

    @Test("first(where:) rethrows the error of a throwing predicate")
    func firstWhereRethrowsPredicateError() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        await #expect(throws: Failure(code: 2)) {
            try await withThrowingTimeout(.seconds(30)) {
                try await flow.first(where: { value in
                    if value == 2 { throw Failure(code: value) }
                    return false
                })
            }
        }
    }

    @Test("first(where:) rethrows the flow error when no value matched before it")
    func firstWhereRethrowsFlowErrorBeforeMatch() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Failure(code: 44)
        }
        await #expect(throws: Failure(code: 44)) {
            try await withThrowingTimeout(.seconds(30)) {
                try await flow.first(where: { $0 > 1 })
            }
        }
    }

    @Test("first(where:) does not run the predicate on values that arrive after the match")
    func firstWhereIgnoresValuesAfterMatch() async throws {
        // This producer never looks at cancellation, so 3 and 4 always arrive
        // after the match.
        let flow = ThrowingFlow(of: 1, 2, 3, 4)
        let tested = Recorder<Int>()
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { value in
                tested.record(value)
                if value > 2 { throw Failure(code: value) }
                return value == 2
            })
        }
        #expect(result == 2)
        #expect(tested.elements == [1, 2])
    }

    @Test("first(where:) awaits an asynchronous predicate")
    func firstWhereAwaitsAsyncPredicate() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { value in
                await Task.yield()
                return value.isMultiple(of: 2)
            })
        }
        #expect(result == 2)
    }

    @Test("first(where:) finds the last value of a long flow")
    func firstWhereFindsLastValueOfLongFlow() async throws {
        let flow = ThrowingFlow(1...100_000)
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { $0 == 100_000 })
        }
        #expect(result == 100_000)
    }

    // MARK: - Cancellation

    @Test("first throws CancellationError when the caller is cancelled on a silent flow")
    func firstThrowsCancellationErrorWhenCallerCancelled() async throws {
        let started = Signal()
        let tornDown = Signal()
        let flow = openFlow(started: started, tornDown: tornDown)
        let task = Task { try await flow.first() }
        #expect(await started.fires())
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await withThrowingTimeout(.seconds(30)) { try await task.value }
        }
        #expect(tornDown.hasFired)
    }

    @Test("first throws CancellationError when a cancelled upstream ends without an error")
    func firstThrowsCancellationErrorWhenUpstreamSwallowsCancellation() async throws {
        let started = Signal()
        let flow = ThrowingFlow<Int> { _ in
            started.fire()
            await parkUntilCancelled()
        }
        let task = Task { try await flow.first() }
        #expect(await started.fires())
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await withThrowingTimeout(.seconds(30)) { try await task.value }
        }
    }

    @Test("first(where:) throws CancellationError when the caller is cancelled before a match")
    func firstWhereThrowsCancellationErrorWhenCallerCancelled() async throws {
        let started = Signal()
        let tornDown = Signal()
        let flow = openFlow(1, 2, started: started, tornDown: tornDown)
        let task = Task { try await flow.first(where: { $0 > 2 }) }
        #expect(await started.fires())
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await withThrowingTimeout(.seconds(30)) { try await task.value }
        }
        #expect(tornDown.hasFired)
    }

    // MARK: - Concurrency and isolation

    @Test("fifty concurrent callers of first on one cold flow each get the first value")
    func concurrentCallersEachGetFirstValue() async throws {
        let runs = Recorder<Int>()
        let flow = ThrowingFlow<Int> { collector in
            runs.record(0)
            try await collector.emit(11)
            try await Task.sleep(for: .seconds(1 << 40))
        }
        let results = try await withThrowingTimeout(.seconds(30)) {
            try await withThrowingTaskGroup(of: Int?.self) { group in
                for _ in 0..<50 {
                    group.addTask { try await flow.first() }
                }
                var collected: [Int?] = []
                for try await result in group { collected.append(result) }
                return collected
            }
        }
        #expect(results == Array(repeating: 11, count: 50))
        #expect(runs.count == 50)
    }

    @Test("first(where:) keeps the first match when a slower predicate matches after it")
    func firstWhereKeepsFirstMatchUnderConcurrentEmitters() async throws {
        let slowPredicateEntered = Signal()
        let flow = ThrowingFlow<Int> { collector in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await collector.emit(1) }
                group.addTask {
                    await slowPredicateEntered.wait()
                    try await collector.emit(2)
                }
                try await group.waitForAll()
            }
        }
        let result = try await withThrowingTimeout(.seconds(30)) {
            try await flow.first(where: { value in
                if value == 1 {
                    // Holds this match back until 2 is taken and the stop
                    // cancels the producer.
                    slowPredicateEntered.fire()
                    await parkUntilCancelled()
                }
                return true
            })
        }
        #expect(result == 2)
    }

    @Test("first returns its value to a main actor caller")
    @MainActor
    func firstReturnsToMainActorCaller() async throws {
        let flow = ThrowingFlow(of: "a", "b")
        let result = try await flow.first()
        #expect(result == "a")
    }

    // MARK: - Fuzz

    @Test("Seeded fuzz of values, thresholds and failure positions matches a hand-walked answer")
    func seededFuzzMatchesHandWalkedAnswer() async throws {
        print("ThrowingFlow first fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)
        for _ in 0..<300 {
            let values = (0..<Int.random(in: 0...12, using: &generator)).map { _ in
                Int.random(in: 0...9, using: &generator)
            }
            let threshold = Int.random(in: 0...10, using: &generator)
            // The flow throws before the value at this index. An index past
            // the end means that it completes normally.
            let failureIndex = Int.random(in: 0...16, using: &generator)

            var expected: Result<Int?, Failure> = .success(nil)
            for (index, value) in values.enumerated() {
                if index == failureIndex {
                    expected = .failure(Failure(code: index))
                    break
                }
                if value >= threshold {
                    expected = .success(value)
                    break
                }
            }
            if case .success(nil) = expected, failureIndex == values.count {
                expected = .failure(Failure(code: failureIndex))
            }

            let flow = ThrowingFlow<Int> { collector in
                for (index, value) in values.enumerated() {
                    if index == failureIndex { throw Failure(code: index) }
                    try await collector.emit(value)
                }
                if failureIndex == values.count { throw Failure(code: failureIndex) }
            }
            let actual: Result<Int?, Failure>
            do {
                actual = .success(try await flow.first(where: { $0 >= threshold }))
            } catch let failure as Failure {
                actual = .failure(failure)
            }
            #expect(
                actual == expected,
                "values \(values), threshold \(threshold), failure index \(failureIndex)"
            )
        }
    }
}

/// Deterministic generator so the fuzz run can be repeated from the printed seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
