import Testing
import FlowSharedModels
import FlowTestSupport
@testable import FlowCore

/// The failure a producer under test closes its flow with.
private enum BridgeError: Error, Equatable {
    case failed(Int)
    case teardown
}

/// What one collection of a throwing flow delivered.
private struct Outcome<Element: Sendable & Equatable>: Sendable {
    var values: [Element]
    var error: (any Error)?
}

/// Collects the flow to its end and keeps the values next to the thrown error.
/// FlowCoreTests cannot use the `toArray` of FlowOperators.
private func collected<Element: Sendable & Equatable>(_ flow: ThrowingFlow<Element>) async -> Outcome<Element> {
    let values = Mutex<[Element]>([])
    do {
        try await flow.collect { value in values.withLock { $0.append(value) } }
        return Outcome(values: values.withLock { $0 }, error: nil)
    } catch {
        return Outcome(values: values.withLock { $0 }, error: error)
    }
}

/// Deterministic generator so the fuzz can be repeated from the printed seed.
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

@Suite("ThrowingFlow channelFlow / callbackFlow builders")
struct ThrowingChannelFlowTests {
    // MARK: - Success

    @Test("Three values then close(throwing:) delivers the three values, then throws the same error")
    func valuesThenFailure() async {
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.trySend(3)
            scope.close(throwing: BridgeError.failed(7))
            await scope.awaitClose()
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [1, 2, 3])
        #expect(outcome.error as? BridgeError == .failed(7))
    }

    @Test("close() after values completes the flow without an error")
    func closeCompletesWithoutError() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.close()
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [1, 2])
        #expect(outcome.error == nil)
    }

    @Test("A producer that returns without close completes the flow without an error")
    func producerReturnCompletes() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(10)
            scope.trySend(20)
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [10, 20])
        #expect(outcome.error == nil)
    }

    @Test("An error thrown from the block delivers the sent values, then fails the flow with it")
    func blockThrowFailsTheFlow() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            throw BridgeError.failed(3)
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [1, 2])
        #expect(outcome.error as? BridgeError == .failed(3))
    }

    @Test("awaitClose teardown runs once when the producer closes with an error")
    func teardownRunsOnFailure() async {
        let teardowns = Mutex(0)
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(42)
            scope.close(throwing: BridgeError.failed(1))
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [42])
        #expect(outcome.error as? BridgeError == .failed(1))
        #expect(teardowns.withLock { $0 } == 1)
    }

    @Test("A failure from a callback on another task wakes awaitClose and reaches the collector")
    func failureFromAnotherTask() async {
        let registered = Signal()
        let handle = Mutex<ThrowingProducerScope<Int>?>(nil)
        let teardowns = Mutex(0)
        let flow = ThrowingFlow<Int>.callbackFlow(bufferCapacity: 0) { scope in
            handle.withLock { $0 = scope }
            registered.fire()
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let collecting = Task { await collected(flow) }
        await registered.wait()
        let scope = handle.withLock { $0 }
        scope?.trySend(5)
        scope?.close(throwing: BridgeError.failed(9))
        let outcome = await collecting.value
        #expect(outcome.values == [5])
        #expect(outcome.error as? BridgeError == .failed(9))
        #expect(teardowns.withLock { $0 } == 1)
    }

    @Test("Re-collecting runs the producer again and each collection gets its own values and error")
    func coldReCollectionIsIndependent() async {
        let runs = Mutex(0)
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            let run = runs.withLock { count -> Int in
                count += 1
                return count
            }
            scope.trySend(run)
            scope.close(throwing: BridgeError.failed(run))
        }
        let first = await collected(flow)
        let second = await collected(flow)
        #expect(first.values == [1])
        #expect(first.error as? BridgeError == .failed(1))
        #expect(second.values == [2])
        #expect(second.error as? BridgeError == .failed(2))
    }

    // MARK: - Buffering / backpressure

    @Test("send suspends the producer while the buffer is full under .suspend")
    func sendBackpressuresProducer() async {
        let log = Recorder<String>()
        let releaseFirst = Signal()

        let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .suspend) { scope in
            let first = await scope.send(1)
            log.record("sent-1:\(first)")
            let second = await scope.send(2)
            log.record("sent-2:\(second)")
            scope.close(throwing: BridgeError.failed(2))
        }

        let collecting = Task {
            await collected(
                ThrowingFlow<Int> { collector in
                    try await flow.collect { value in
                        if value == 1 { await releaseFirst.wait() }
                        log.record("consumed-\(value)")
                        try await collector.emit(value)
                    }
                }
            )
        }

        await log.wait { $0.contains("sent-1:enqueued") }
        for _ in 0..<100 { await Task.yield() }
        #expect(
            !log.elements.contains { $0.hasPrefix("sent-2") },
            "with capacity 1 and an unconsumed value, the second send must stay suspended"
        )

        releaseFirst.fire()
        let outcome = await collecting.value
        #expect(outcome.values == [1, 2])
        #expect(outcome.error as? BridgeError == .failed(2))
        let entries = log.elements
        let consumedFirst = try? #require(entries.firstIndex(of: "consumed-1"))
        let sentSecond = try? #require(entries.firstIndex(of: "sent-2:enqueued"))
        if let consumedFirst, let sentSecond {
            #expect(consumedFirst < sentSecond, "the suspended send resumes only after the first value is consumed")
        }
    }

    @Test("A failure wakes a producer suspended in send, which reports closed")
    func failureUnblocksSuspendedSend() async {
        let suspendedResult = Mutex<ChannelSendResult?>(nil)
        let firstDelivered = Signal()
        let handle = Mutex<ThrowingProducerScope<Int>?>(nil)
        let release = Signal()

        let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .suspend) { scope in
            handle.withLock { $0 = scope }
            await scope.send(1)
            let result = await scope.send(2)
            suspendedResult.withLock { $0 = result }
        }
        let collecting = Task {
            await collected(
                ThrowingFlow<Int> { collector in
                    try await flow.collect { value in
                        firstDelivered.fire()
                        await release.wait()
                        try await collector.emit(value)
                    }
                }
            )
        }
        await firstDelivered.wait()
        handle.withLock { $0 }?.close(throwing: BridgeError.failed(4))
        release.fire()
        let outcome = await collecting.value
        #expect(suspendedResult.withLock { $0 } == .closed)
        #expect(outcome.values == [1])
        #expect(outcome.error as? BridgeError == .failed(4))
    }

    @Test("dropOldest conflates buffered values and still delivers the error after them")
    func dropOldestThenFailure() async {
        let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            for index in 1...100 { scope.trySend(index) }
            scope.close(throwing: BridgeError.failed(100))
        }
        let outcome = await collected(flow)
        #expect(outcome.values.last == 100)
        #expect(outcome.values == outcome.values.sorted())
        #expect(outcome.error as? BridgeError == .failed(100))
    }

    @Test("Ten thousand values buffered without a bound all arrive in order before the error")
    func hugeInputThenFailure() async {
        let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 0) { scope in
            for index in 0..<10_000 { scope.trySend(index) }
            scope.close(throwing: BridgeError.failed(0))
        }
        let outcome = await collected(flow)
        #expect(outcome.values == Array(0..<10_000))
        #expect(outcome.error as? BridgeError == .failed(0))
    }

    // MARK: - Developer misuse

    @Test("close(throwing:) then close() keeps the error")
    func failureThenCloseKeepsTheError() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.close(throwing: BridgeError.failed(1))
            scope.close()
        }
        let outcome = await collected(flow)
        #expect(outcome.values.isEmpty)
        #expect(outcome.error as? BridgeError == .failed(1))
    }

    @Test("close() then close(throwing:) completes without an error")
    func closeThenFailureIgnoresTheError() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.close()
            scope.close(throwing: BridgeError.failed(1))
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [1])
        #expect(outcome.error == nil)
    }

    @Test("The first of two close(throwing:) calls wins")
    func firstFailureWins() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.close(throwing: BridgeError.failed(1))
            scope.close(throwing: BridgeError.failed(2))
        }
        let outcome = await collected(flow)
        #expect(outcome.error as? BridgeError == .failed(1))
    }

    @Test("An error thrown from the block after close() is ignored")
    func throwAfterCloseIsIgnored() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.close()
            throw BridgeError.failed(1)
        }
        let outcome = await collected(flow)
        #expect(outcome.values == [1])
        #expect(outcome.error == nil)
    }

    @Test("trySend and send after close(throwing:) report closed and deliver nothing")
    func sendAfterFailureIsClosed() async {
        let results = Mutex<[ChannelSendResult]>([])
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.close(throwing: BridgeError.failed(1))
            let tried = scope.trySend(98)
            let sent = await scope.send(99)
            results.withLock { $0 = [tried, sent] }
        }
        let outcome = await collected(flow)
        #expect(results.withLock { $0 } == [.closed, .closed])
        #expect(outcome.values.isEmpty)
        #expect(outcome.error as? BridgeError == .failed(1))
    }

    @Test("trySend after close() reports closed and delivers nothing")
    func trySendAfterCloseIsClosed() async {
        let result = Mutex<ChannelSendResult?>(nil)
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.close()
            result.withLock { $0 = scope.trySend(99) }
        }
        let outcome = await collected(flow)
        #expect(result.withLock { $0 } == .closed)
        #expect(outcome.values.isEmpty)
        #expect(outcome.error == nil)
    }

    #if DEBUG && (os(macOS) || os(Linux))
    @Test("callbackFlow asserts in debug builds when the block returns without awaitClose or close")
    func callbackFlowAssertsWithoutAwaitClose() async {
        await #expect(processExitsWith: .failure) {
            let flow = ThrowingFlow<Int>.callbackFlow { scope in
                scope.trySend(1)
            }
            try await flow.collect { _ in }
        }
    }

    @Test("callbackFlow does not assert when the block closes or throws")
    func callbackFlowAcceptsCloseAndThrow() async {
        await #expect(processExitsWith: .success) {
            let closing = ThrowingFlow<Int>.callbackFlow { scope in scope.close() }
            try await closing.collect { _ in }
            let throwing = ThrowingFlow<Int>.callbackFlow { _ in throw BridgeError.failed(1) }
            try? await throwing.collect { _ in }
        }
    }
    #endif

    // MARK: - Cancellation and downstream failure

    @Test("Cancelling the collector runs onClose once and reports no error")
    func cancellationTearsDownWithoutError() async {
        let teardowns = Mutex(0)
        let started = Signal()
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(1)
            started.fire()
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let task = Task { await collected(flow) }
        await started.wait()
        task.cancel()
        let outcome = await task.value
        #expect(teardowns.withLock { $0 } == 1)
        #expect(outcome.error == nil, "cancellation is not a failure of the flow")
    }

    @Test("An error the producer raises because it was cancelled is not reported as a failure")
    func failureAfterCancellationIsIgnored() async {
        let started = Signal()
        let handle = Mutex<ThrowingProducerScope<Int>?>(nil)
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            handle.withLock { $0 = scope }
            started.fire()
            await scope.awaitClose()
            throw BridgeError.teardown
        }
        let task = Task { await collected(flow) }
        await started.wait()
        task.cancel()
        let outcome = await task.value
        #expect(outcome.error == nil)
        handle.withLock { $0 }?.close(throwing: BridgeError.failed(1))
        #expect(handle.withLock { $0 }?.trySend(1) == .closed)
    }

    @Test("A block that throws because its own work was cancelled does not fail the flow")
    func cancelledBlockThrowIsIgnored() async {
        let started = Signal()
        let flow = ThrowingFlow<Int>.channelFlow { _ in
            started.fire()
            await parkUntilCancelled()
            throw BridgeError.teardown
        }
        let task = Task { await collected(flow) }
        await started.wait()
        task.cancel()
        let outcome = await task.value
        #expect(outcome.error == nil)
    }

    @Test("An error thrown by the collector stops the flow, tears down once and is rethrown")
    func downstreamErrorTearsDown() async {
        let teardowns = Mutex(0)
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let seen = Mutex<[Int]>([])
        var thrown: (any Error)?
        do {
            try await flow.collect { value in
                seen.withLock { $0.append(value) }
                throw BridgeError.failed(value)
            }
        } catch {
            thrown = error
        }
        #expect(seen.withLock { $0 } == [1], "no value is delivered after the collector failed")
        #expect(thrown as? BridgeError == .failed(1))
        #expect(teardowns.withLock { $0 } == 1)
    }

    @Test("The collector's own error wins over a producer failure that arrives later")
    func downstreamErrorWinsOverLaterFailure() async {
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(1)
            await scope.awaitClose()
            scope.close(throwing: BridgeError.teardown)
        }
        var thrown: (any Error)?
        do {
            try await flow.collect { value in throw BridgeError.failed(value) }
        } catch {
            thrown = error
        }
        #expect(thrown as? BridgeError == .failed(1))
    }

    // MARK: - Fuzz / adversarial

    @Test("Cancellation storm tears down once per collection and never reports an error")
    func cancellationStorm() async {
        let teardowns = Mutex(0)
        let errors = Mutex(0)
        let flow = ThrowingFlow<Int>.callbackFlow { scope in
            scope.trySend(1)
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let iterations = 200
        for _ in 0..<iterations {
            let task = Task { await collected(flow) }
            task.cancel()
            if await task.value.error != nil { errors.withLock { $0 += 1 } }
        }
        #expect(teardowns.withLock { $0 } == iterations)
        #expect(errors.withLock { $0 } == 0)
    }

    @Test("Concurrent close(throwing:) callers: exactly one of their errors is thrown and every value sent first arrives")
    func concurrentFailuresPickOne() async {
        for _ in 0..<50 {
            let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 0) { scope in
                for index in 0..<20 { scope.trySend(index) }
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<32 {
                        group.addTask { scope.close(throwing: BridgeError.failed(index)) }
                    }
                    await group.waitForAll()
                }
            }
            let outcome = await collected(flow)
            #expect(outcome.values == Array(0..<20))
            guard case .failed(let winner)? = outcome.error as? BridgeError else {
                Issue.record("expected one of the racing errors, got \(String(describing: outcome.error))")
                continue
            }
            #expect((0..<32).contains(winner))
        }
    }

    @Test("Concurrent trySend and close(throwing:) deliver no duplicate or phantom value, and the error always arrives")
    func concurrentSendAndFailureIntegrity() async {
        for _ in 0..<50 {
            let sent = 200
            let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 0) { scope in
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<sent {
                        group.addTask { scope.trySend(index) }
                    }
                    group.addTask { scope.close(throwing: BridgeError.failed(sent)) }
                    await group.waitForAll()
                }
            }
            let outcome = await collected(flow)
            #expect(Set(outcome.values).count == outcome.values.count)
            #expect(outcome.values.allSatisfy { (0..<sent).contains($0) })
            #expect(outcome.error as? BridgeError == .failed(sent))
        }
    }

    @Test("Two collectors of the same flow each get the full values and the error")
    func concurrentCollectorsAreIndependent() async {
        let flow = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.close(throwing: BridgeError.failed(2))
        }
        async let first = collected(flow)
        async let second = collected(flow)
        let (a, b) = await (first, second)
        #expect(a.values == [1, 2])
        #expect(b.values == [1, 2])
        #expect(a.error as? BridgeError == .failed(2))
        #expect(b.error as? BridgeError == .failed(2))
    }

    @Test("Seeded fuzz: every value sent before the end arrives in order, and an error is thrown only when the producer failed")
    func seededFuzzOfEndings() async {
        let seed: UInt64 = 20_261_124
        print("Throwing channelFlow fuzz seed: \(seed)")
        var generator = SplitMix64(state: seed)
        for round in 0..<300 {
            let count = Int.random(in: 0...40, using: &generator)
            let lateSends = Int.random(in: 0...5, using: &generator)
            let ending = Int.random(in: 0...3, using: &generator)
            let flow = ThrowingFlow<Int>.channelFlow(bufferCapacity: 0) { scope in
                for index in 0..<count { scope.trySend(index) }
                switch ending {
                case 0: scope.close()
                case 1: scope.close(throwing: BridgeError.failed(round))
                case 2: throw BridgeError.failed(round)
                default: break
                }
                // Sends after the end must never arrive.
                if ending < 2 {
                    for index in 0..<lateSends { scope.trySend(1_000 + index) }
                }
            }
            let outcome = await collected(flow)
            #expect(outcome.values == Array(0..<count), "round \(round), seed \(seed)")
            let expectsFailure = ending == 1 || ending == 2
            #expect(
                outcome.error as? BridgeError == (expectsFailure ? .failed(round) : nil),
                "round \(round), seed \(seed)"
            )
        }
    }
}
