import Testing
import FlowCore
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

/// A collector running in its own task. It records what it receives and
/// reports when `collect` returns.
private final class RunningCollector: Sendable {
    let received = Recorder<Int>()
    let returned = Signal()
    private let task: Task<Void, Never>

    /// - Parameter onValue: Runs for each value after it is recorded, so a
    ///   test can hold the collector inside its action.
    init(_ flow: Flow<Int>, onValue: @escaping @Sendable (Int) async -> Void = { _ in }) {
        let received = received
        let returned = returned
        task = Task {
            await flow.collect { value in
                received.record(value)
                await onValue(value)
            }
            returned.fire()
        }
    }

    func cancel() { task.cancel() }
}

/// Deterministic generator so a fuzz run can be repeated from the printed seed.
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

@Suite("MutableSharedFlow close")
struct MutableSharedFlowCloseTests {
    private static let fuzzSeed: UInt64 = 20_261_124

    @Test("close returns every collector after it has received all emitted values")
    func closeCompletesCollectorsAfterTheirValues() async throws {
        let flow = MutableSharedFlow<Int>()
        let first = RunningCollector(flow.asFlow())
        let second = RunningCollector(flow.asFlow())
        try await flow.waitForSubscribers(2)

        await flow.emit(1)
        await flow.emit(2)
        await flow.emit(3)
        await flow.close()

        #expect(await first.returned.fires(), "first collector did not return after close")
        #expect(await second.returned.fires(), "second collector did not return after close")
        #expect(first.received.elements == [1, 2, 3])
        #expect(second.received.elements == [1, 2, 3])
    }

    @Test("an open flow keeps its collector suspended")
    func openFlowDoesNotComplete() async throws {
        let flow = MutableSharedFlow<Int>()
        let collector = RunningCollector(flow.asFlow())
        defer { collector.cancel() }
        try await flow.waitForSubscribers(1)

        await flow.emit(1)
        await collector.received.wait(atLeast: 1)

        #expect(!(await collector.returned.firesWithinHops()), "collector returned without a close")
    }

    @Test("close lets a slow collector drain the values buffered for it")
    func closeDrainsBufferedValues() async throws {
        let flow = MutableSharedFlow<Int>()
        let gate = Signal()
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        try await flow.waitForSubscribers(1)

        await flow.emit(1)
        await flow.emit(2)
        await flow.emit(3)
        await collector.received.wait(atLeast: 1)
        await flow.close()

        #expect(!(await collector.returned.firesWithinHops()), "collector returned before it drained")
        gate.fire()
        #expect(await collector.returned.fires(), "slow collector did not return after close")
        #expect(collector.received.elements == [1, 2, 3])
    }

    @Test("a collector that attaches after close returns at once without the replay")
    func lateCollectorCompletesAtOnce() async {
        let flow = MutableSharedFlow<Int>(replay: 2)
        await flow.emit(1)
        await flow.emit(2)
        await flow.close()

        let late = RunningCollector(flow.asFlow())

        #expect(await late.returned.fires(), "late collector did not return on a closed flow")
        #expect(late.received.elements == [])
        #expect(await flow.subscriptionCount == 0)
    }

    @Test("closing twice is harmless")
    func closeIsIdempotent() async throws {
        let flow = MutableSharedFlow<Int>()
        let collector = RunningCollector(flow.asFlow())
        try await flow.waitForSubscribers(1)
        await flow.emit(1)

        await flow.close()
        await flow.close()

        #expect(await collector.returned.fires(), "collector did not return after two closes")
        #expect(collector.received.elements == [1])
        let late = RunningCollector(flow.asFlow())
        #expect(await late.returned.fires(), "late collector did not return after two closes")
    }

    @Test("emit after close delivers nothing and leaves the replay cache alone")
    func emitAfterCloseIsIgnored() async throws {
        let flow = MutableSharedFlow<Int>(replay: 1)
        let gate = Signal()
        // Held inside its action, so it is still collecting when the late emit runs.
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        try await flow.waitForSubscribers(1)
        await flow.emit(1)
        await collector.received.wait(atLeast: 1)
        await flow.close()

        await flow.emit(2)
        gate.fire()

        #expect(await collector.returned.fires(), "collector did not return after close")
        #expect(collector.received.elements == [1])
        #expect(await flow.replayCache == [1])
    }

    @Test("waitForSubscribers(atMost: 0) returns after close")
    func closeReleasesAtMostWaiter() async throws {
        let flow = MutableSharedFlow<Int>()
        let gate = Signal()
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        defer { gate.fire() }
        try await flow.waitForSubscribers(1)
        let emptied = Signal()
        let waiter = Task {
            try await flow.waitForSubscribers(atMost: 0)
            emptied.fire()
        }
        defer { waiter.cancel() }
        #expect(!(await emptied.firesWithinHops()), "waiter returned with a collector attached")

        await flow.close()

        #expect(await emptied.fires(), "atMost 0 waiter stayed parked after close")
        #expect(await flow.subscriptionCount == 0)
        _ = collector
    }

    @Test("close reaches collectors of the read-only view")
    func closeCompletesReadOnlyViewCollectors() async throws {
        let flow = MutableSharedFlow<Int>()
        let collector = RunningCollector(flow.asSharedFlow().asFlow())
        try await flow.waitForSubscribers(1)
        await flow.emit(7)

        await flow.close()

        #expect(await collector.returned.fires(), "view collector did not return after close")
        #expect(collector.received.elements == [7])
    }

    @Test("a collector cancelled before close does not disturb close")
    func closeAfterCollectorCancellation() async throws {
        let flow = MutableSharedFlow<Int>()
        let cancelled = RunningCollector(flow.asFlow())
        let kept = RunningCollector(flow.asFlow())
        try await flow.waitForSubscribers(2)
        cancelled.cancel()
        try await flow.waitForSubscribers(atMost: 1)
        await flow.emit(1)

        await flow.close()

        #expect(await kept.returned.fires(), "remaining collector did not return after close")
        #expect(kept.received.elements == [1])
    }

    @Test("emitters racing close never deliver out of order, and every collector returns")
    func concurrentEmittersAndClosers() async throws {
        let flow = MutableSharedFlow<Int>()
        let collectors = (0..<4).map { _ in RunningCollector(flow.asFlow()) }
        try await flow.waitForSubscribers(4)

        await withTaskGroup(of: Void.self) { group in
            // One emitter, so the order of its values is fixed.
            group.addTask {
                for value in 0..<500 { await flow.emit(value) }
            }
            for _ in 0..<4 {
                group.addTask { await flow.close() }
            }
        }
        await flow.emit(-1)

        for collector in collectors {
            #expect(await collector.returned.fires(), "collector did not return after racing closes")
            let received = collector.received.elements
            // Whatever arrived before the close is a prefix of the emitted sequence.
            #expect(received == Array(0..<received.count))
        }
        #expect(await flow.subscriptionCount == 0)
    }

    @Test("seeded fuzz: collectors get exactly the values emitted while attached, then return")
    func seededFuzzOfEmitThenClose() async throws {
        print("MutableSharedFlow close fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)

        for _ in 0..<40 {
            let collectorCount = Int.random(in: 0...5, using: &generator)
            let valueCount = [0, 1, 3, 64, 2000].randomElement(using: &generator) ?? 0
            let ignoredCount = Int.random(in: 0...3, using: &generator)
            let flow = MutableSharedFlow<Int>(replay: Int.random(in: 0...2, using: &generator))
            let collectors = (0..<collectorCount).map { _ in RunningCollector(flow.asFlow()) }
            try await flow.waitForSubscribers(collectorCount)

            for value in 0..<valueCount { await flow.emit(value) }
            await flow.close()
            for value in 0..<ignoredCount { await flow.emit(-1 - value) }

            for collector in collectors {
                #expect(await collector.returned.fires(), "collector did not return after close")
                #expect(collector.received.elements == Array(0..<valueCount))
            }
        }
    }
}

@Suite("MutableStateFlow close")
struct MutableStateFlowCloseTests {
    private static let fuzzSeed: UInt64 = 20_261_125

    @Test("close returns every collector after it has received all updates")
    func closeCompletesCollectorsAfterTheirValues() async throws {
        let flow = MutableStateFlow(0)
        let first = RunningCollector(flow.asFlow())
        let second = RunningCollector(flow.asFlow())
        try await flow.waitForSubscribers(2)
        await first.received.wait(atLeast: 1)
        await second.received.wait(atLeast: 1)

        flow.value = 1
        flow.value = 2
        flow.value = 3
        flow.close()

        #expect(await first.returned.fires(), "first collector did not return after close")
        #expect(await second.returned.fires(), "second collector did not return after close")
        #expect(first.received.elements == [0, 1, 2, 3])
        #expect(second.received.elements == [0, 1, 2, 3])
    }

    @Test("an open flow keeps its collector suspended")
    func openFlowDoesNotComplete() async throws {
        let flow = MutableStateFlow(0)
        let collector = RunningCollector(flow.asFlow())
        defer { collector.cancel() }
        await collector.received.wait(atLeast: 1)

        #expect(!(await collector.returned.firesWithinHops()), "collector returned without a close")
    }

    @Test("close lets a slow collector drain the updates buffered for it")
    func closeDrainsBufferedValues() async throws {
        let flow = MutableStateFlow(0)
        let gate = Signal()
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        await collector.received.wait(atLeast: 1)

        flow.value = 1
        flow.value = 2
        flow.close()

        #expect(!(await collector.returned.firesWithinHops()), "collector returned before it drained")
        gate.fire()
        #expect(await collector.returned.fires(), "slow collector did not return after close")
        #expect(collector.received.elements == [0, 1, 2])
    }

    @Test("a collector that attaches after close receives the last value, then returns")
    func lateCollectorGetsLastValueThenCompletes() async throws {
        let flow = MutableStateFlow(0)
        flow.value = 5
        flow.close()

        let late = RunningCollector(flow.asFlow())

        #expect(await late.returned.fires(), "late collector did not return on a closed flow")
        #expect(late.received.elements == [5])
        try await flow.waitForSubscribers(atMost: 0)
        #expect(await flow.subscriptionCount == 0)
    }

    @Test("closing twice is harmless")
    func closeIsIdempotent() async {
        let flow = MutableStateFlow(0)
        let collector = RunningCollector(flow.asFlow())
        await collector.received.wait(atLeast: 1)

        flow.close()
        flow.close()

        #expect(await collector.returned.fires(), "collector did not return after two closes")
        #expect(collector.received.elements == [0])
        let late = RunningCollector(flow.asFlow())
        #expect(await late.returned.fires(), "late collector did not return after two closes")
        #expect(late.received.elements == [0])
    }

    @Test("writes after close change nothing and deliver nothing")
    func writesAfterCloseAreIgnored() async {
        let flow = MutableStateFlow(1)
        let gate = Signal()
        // Held inside its action, so it is still collecting when the late writes run.
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        await collector.received.wait(atLeast: 1)
        flow.close()

        flow.value = 2
        flow.send(3)
        #expect(!flow.compareAndSet(expected: 1, newValue: 4))
        #expect(flow.value == 1)
        gate.fire()

        #expect(await collector.returned.fires(), "collector did not return after close")
        #expect(collector.received.elements == [1])
        #expect(flow.value == 1)
    }

    @Test("the update family returns the last value on a closed flow without running the transform")
    func updateFamilyOnClosedFlow() async {
        let flow = MutableStateFlow(1)
        flow.close()
        let transformRuns = Recorder<Int>()
        let finished = Signal()
        let results = Recorder<Int>()

        // Off the test task, so a retry loop that never ends fails by name.
        Task.detached {
            flow.update { transformRuns.record($0); return $0 + 1 }
            results.record(flow.getAndUpdate { transformRuns.record($0); return $0 + 1 })
            results.record(flow.updateAndGet { transformRuns.record($0); return $0 + 1 })
            finished.fire()
        }

        #expect(await finished.fires(), "an update on a closed flow did not return")
        #expect(results.elements == [1, 1])
        #expect(transformRuns.elements == [])
        #expect(flow.value == 1)
    }

    @Test("compareAndSet to the current value still reports a match on a closed flow")
    func compareAndSetNoChangeOnClosedFlow() {
        let flow = MutableStateFlow(1)
        flow.close()

        #expect(flow.compareAndSet(expected: 1, newValue: 1))
        #expect(!flow.compareAndSet(expected: 2, newValue: 1))
    }

    @Test("waitForSubscribers(atMost: 0) returns after close")
    func closeReleasesAtMostWaiter() async throws {
        let flow = MutableStateFlow(0)
        let gate = Signal()
        let collector = RunningCollector(flow.asFlow()) { _ in await gate.wait() }
        defer { gate.fire() }
        await collector.received.wait(atLeast: 1)
        let emptied = Signal()
        let waiter = Task {
            try await flow.waitForSubscribers(atMost: 0)
            emptied.fire()
        }
        defer { waiter.cancel() }
        #expect(!(await emptied.firesWithinHops()), "waiter returned with a collector attached")

        flow.close()

        #expect(await emptied.fires(), "atMost 0 waiter stayed parked after close")
        #expect(await flow.subscriptionCount == 0)
    }

    @Test("close reaches collectors of the read-only view, and the view still reads the last value")
    func closeCompletesReadOnlyViewCollectors() async {
        let flow = MutableStateFlow(0)
        let view = flow.asStateFlow()
        let collector = RunningCollector(view.asFlow())
        await collector.received.wait(atLeast: 1)
        flow.value = 9

        flow.close()

        #expect(await collector.returned.fires(), "view collector did not return after close")
        #expect(collector.received.elements == [0, 9])
        #expect(view.value == 9)
    }

    @Test("a collector cancelled before close does not disturb close")
    func closeAfterCollectorCancellation() async throws {
        let flow = MutableStateFlow(0)
        let cancelled = RunningCollector(flow.asFlow())
        let kept = RunningCollector(flow.asFlow())
        try await flow.waitForSubscribers(2)
        await kept.received.wait(atLeast: 1)
        cancelled.cancel()
        try await flow.waitForSubscribers(atMost: 1)
        flow.value = 1

        flow.close()

        #expect(await kept.returned.fires(), "remaining collector did not return after close")
        #expect(kept.received.elements == [0, 1])
    }

    @Test("writers racing close leave every collector on the final value, in order")
    func concurrentWritersAndClosers() async throws {
        let flow = MutableStateFlow(0)
        let collectors = (0..<4).map { _ in RunningCollector(flow.asFlow()) }
        for collector in collectors { await collector.received.wait(atLeast: 1) }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<500 { flow.update { $0 + 1 } }
                }
            }
            for _ in 0..<4 {
                group.addTask { flow.close() }
            }
        }
        let final = flow.value
        flow.value = -1

        #expect(flow.value == final)
        for collector in collectors {
            #expect(await collector.returned.fires(), "collector did not return after racing closes")
            let received = collector.received.elements
            // Every applied increment was delivered, so nothing is skipped or reordered.
            #expect(received == Array(0...final))
        }
    }

    @Test("seeded fuzz: collectors get every update made before close, then return")
    func seededFuzzOfUpdateThenClose() async throws {
        print("MutableStateFlow close fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)

        for _ in 0..<40 {
            let collectorCount = Int.random(in: 0...5, using: &generator)
            let updateCount = [0, 1, 3, 64, 2000].randomElement(using: &generator) ?? 0
            let ignoredCount = Int.random(in: 0...3, using: &generator)
            let flow = MutableStateFlow(0)
            let collectors = (0..<collectorCount).map { _ in RunningCollector(flow.asFlow()) }
            for collector in collectors { await collector.received.wait(atLeast: 1) }

            for value in 0..<updateCount { flow.value = value + 1 }
            flow.close()
            for value in 0..<ignoredCount { flow.value = -1 - value }

            #expect(flow.value == updateCount)
            for collector in collectors {
                #expect(await collector.returned.fires(), "collector did not return after close")
                #expect(collector.received.elements == Array(0...updateCount))
            }
        }
    }
}
