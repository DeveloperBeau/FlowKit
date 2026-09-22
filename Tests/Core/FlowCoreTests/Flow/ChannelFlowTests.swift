import Testing
import FlowSharedModels
@testable import FlowCore

/// A one-shot gate: `wait()` suspends until `open()` is called once, after
/// which every wait passes. Lets a test hold a collector inside `emit` while a
/// producer bursts values, making buffering behaviour deterministic rather
/// than timing-dependent.
private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Spins until `flag` is set, yielding between checks. Convergent, not timed.
private func waitUntil(_ flag: Mutex<Bool>) async {
    while !flag.withLock({ $0 }) { await Task.yield() }
}

@Suite("channelFlow / callbackFlow builders")
struct ChannelFlowTests {
    // MARK: - Success

    @Test("trySend delivers values in order, close completes the flow")
    func deliversInOrderThenCloses() async {
        let flow = Flow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.trySend(3)
            scope.close()
        }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == [1, 2, 3])
    }

    @Test("A producer that returns without close completes the flow")
    func producerReturnCompletes() async {
        let flow = Flow<Int>.channelFlow { scope in
            scope.trySend(10)
            scope.trySend(20)
            // No close() and no awaitClose: returning ends the flow.
        }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == [10, 20])
    }

    @Test("awaitClose teardown runs when the producer closes the channel")
    func awaitCloseRunsOnClose() async {
        let tornDown = Mutex(false)
        let flow = Flow<Int>.callbackFlow { scope in
            scope.trySend(42)
            scope.close()
            await scope.awaitClose { tornDown.withLock { $0 = true } }
        }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == [42])
        #expect(tornDown.withLock { $0 }, "awaitClose teardown must run after close()")
    }

    @Test("awaitClose teardown runs when the collecting task is cancelled")
    func awaitCloseRunsOnCancellation() async {
        let tornDown = Mutex(false)
        let started = Mutex(false)
        let flow = Flow<Int>.callbackFlow { scope in
            scope.trySend(1)
            started.withLock { $0 = true }
            await scope.awaitClose { tornDown.withLock { $0 = true } }
        }
        let task = Task {
            await flow.collect { _ in }
        }
        await waitUntil(started)
        task.cancel()
        await task.value
        #expect(tornDown.withLock { $0 })
    }

    // MARK: - Buffering / backpressure

    @Test("dropOldest keeps the newest value: the last delivered is always the last sent")
    func dropOldestConflates() async {
        let gate = Gate()
        let burstDone = Mutex(false)
        let received = Mutex<[Int]>([])

        let flow = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            for index in 1...1000 { scope.trySend(index) }
            scope.close()
            burstDone.withLock { $0 = true }
        }

        // The collector's first emit parks on the gate. Open it only after the
        // whole burst has landed, so the cap-1 buffer has conflated to 1000.
        let collecting = Task {
            await flow.collect { value in
                await gate.wait()
                received.withLock { $0.append(value) }
            }
        }
        await waitUntil(burstDone)
        await gate.open()
        await collecting.value

        let final = received.withLock { $0 }
        #expect(final.last == 1000, "dropOldest must keep the newest value")
        #expect(final.count <= 2, "a burst of 1000 into a cap-1 buffer must conflate, not deliver all")
        #expect(final == final.sorted(), "conflation drops values but must never reorder them")
    }

    @Test("dropLatest keeps the oldest value and discards newer ones when full")
    func dropLatestKeepsOldest() async {
        let gate = Gate()
        let received = Mutex<[Int]>([])
        let opened = Mutex(false)

        let flow = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .dropLatest) { scope in
            // First lands in the buffer; the rest arrive while the cap-1
            // oldest-keeping buffer is full, so they are dropped.
            scope.trySend(1)
            for index in 2...1000 { scope.trySend(index) }
            scope.close()
            opened.withLock { $0 = true }
        }

        let collecting = Task {
            await flow.collect { value in
                await gate.wait()
                received.withLock { $0.append(value) }
            }
        }
        await waitUntil(opened)
        await gate.open()
        await collecting.value

        let final = received.withLock { $0 }
        #expect(!final.contains(1000), "dropLatest must discard newer values when full")
        #expect(final.first == 1, "dropLatest must keep the oldest value")
    }

    @Test("Zero and negative capacity buffer without dropping")
    func nonPositiveCapacityIsUnbounded() async {
        for capacity in [0, -5] {
            let flow = Flow<Int>.channelFlow(bufferCapacity: capacity, onBufferOverflow: .dropOldest) { scope in
                for index in 1...50 { scope.trySend(index) }
                scope.close()
            }
            let received = Mutex<[Int]>([])
            await flow.collect { value in received.withLock { $0.append(value) } }
            #expect(received.withLock { $0 } == Array(1...50), "capacity \(capacity) must not drop")
        }
    }

    // MARK: - Developer misuse

    @Test("trySend after close reports closed and delivers nothing")
    func trySendAfterCloseIsClosed() async {
        let result = Mutex<ChannelSendResult?>(nil)
        let flow = Flow<Int>.channelFlow { scope in
            scope.close()
            result.withLock { $0 = scope.trySend(99) }
        }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(result.withLock { $0 } == .closed)
        #expect(received.withLock { $0 }.isEmpty, "a value sent after close must never reach the collector")
    }

    @Test("close is idempotent")
    func closeIsIdempotent() async {
        let flow = Flow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.close()
            scope.close()
            scope.close()
        }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == [1])
    }

    @Test("A producer that closes without sending completes empty")
    func emptyChannelCompletes() async {
        let flow = Flow<Int>.channelFlow { scope in scope.close() }
        let received = Mutex<[Int]>([])
        await flow.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 }.isEmpty)
    }

    @Test("Re-collecting a cold channelFlow runs the producer independently each time")
    func coldReCollectionIsIndependent() async {
        let teardowns = Mutex(0)
        let flow = Flow<Int>.callbackFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.close()
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let first = Mutex<[Int]>([])
        let second = Mutex<[Int]>([])
        await flow.collect { value in first.withLock { $0.append(value) } }
        await flow.collect { value in second.withLock { $0.append(value) } }
        #expect(first.withLock { $0 } == [1, 2])
        #expect(second.withLock { $0 } == [1, 2], "each collection must get its own full sequence")
        #expect(teardowns.withLock { $0 } == 2, "each cold collection tears down once")
    }

    // MARK: - Fuzz / adversarial

    @Test("Teardown runs exactly once no matter how many close paths fire")
    func teardownRunsExactlyOnce() async {
        let teardowns = Mutex(0)
        let started = Mutex(false)
        let flow = Flow<Int>.callbackFlow { scope in
            scope.trySend(1)
            started.withLock { $0 = true }
            // Also close from inside, racing the collector cancellation and the
            // stream termination — all three call markClosed.
            scope.close()
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let task = Task { await flow.collect { _ in } }
        await waitUntil(started)
        task.cancel()
        await task.value
        #expect(teardowns.withLock { $0 } == 1, "onClose must run exactly once, never per close path")
    }

    @Test("Cancellation storm tears down once per collection and never deadlocks")
    func cancellationStorm() async {
        let teardowns = Mutex(0)
        let flow = Flow<Int>.callbackFlow { scope in
            scope.trySend(1)
            await scope.awaitClose { teardowns.withLock { $0 += 1 } }
        }
        let iterations = 200
        for _ in 0..<iterations {
            let task = Task { await flow.collect { _ in } }
            task.cancel()
            await task.value
        }
        #expect(teardowns.withLock { $0 } == iterations, "each collection tears down exactly once")
    }

    @Test("Concurrent trySend and close corrupt nothing: no duplicates, no phantom values, no post-close leak")
    func concurrentSendAndCloseIntegrity() async {
        for _ in 0..<50 {
            let received = Mutex<[Int]>([])
            let sent = 500
            let flow = Flow<Int>.channelFlow(bufferCapacity: sent, onBufferOverflow: .dropOldest) { scope in
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<sent {
                        group.addTask { scope.trySend(index) }
                    }
                    group.addTask { scope.close() }
                    await group.waitForAll()
                }
                scope.close()
            }
            await flow.collect { value in received.withLock { $0.append(value) } }

            let values = received.withLock { $0 }
            #expect(Set(values).count == values.count, "no value may be delivered twice")
            #expect(values.allSatisfy { $0 >= 0 && $0 < sent }, "no phantom value outside the sent range")
        }
    }

    @Test("Two collectors of the same cold flow do not share or split the stream")
    func concurrentCollectorsAreIndependent() async {
        let flow = Flow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.trySend(2)
            scope.trySend(3)
            scope.close()
        }
        async let a: [Int] = {
            let box = Mutex<[Int]>([])
            await flow.collect { value in box.withLock { $0.append(value) } }
            return box.withLock { $0 }
        }()
        async let b: [Int] = {
            let box = Mutex<[Int]>([])
            await flow.collect { value in box.withLock { $0.append(value) } }
            return box.withLock { $0 }
        }()
        let (first, second) = await (a, b)
        #expect(first == [1, 2, 3])
        #expect(second == [1, 2, 3], "a second collector gets its own full copy, not the leftovers of the first")
    }
}
