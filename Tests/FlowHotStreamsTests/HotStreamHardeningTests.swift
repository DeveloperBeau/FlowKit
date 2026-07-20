import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

@Suite("Hot stream hardening")
struct HotStreamHardeningTests {
    // MARK: - Sharing: one upstream for many collectors

    @Test("A shared cold upstream runs once and is multicast, not once per collector")
    func sharedUpstreamStartsOnce() async {
        let starts = Mutex(0)
        // Finite source: emits once and completes, so nothing leaks. The
        // second collector still gets the value from the replay cache.
        let source = Flow<Int> { collector in
            starts.withLock { $0 += 1 }
            await collector.emit(1)
        }
        let shared = source.asSharedFlow(replay: 1)

        let aGot = Mutex(false)
        let bGot = Mutex(false)
        let a = Task { await shared.asFlow().collect { _ in aGot.withLock { $0 = true } } }
        let b = Task { await shared.asFlow().collect { _ in bGot.withLock { $0 = true } } }

        while !(aGot.withLock { $0 } && bGot.withLock { $0 }) { await Task.yield() }
        #expect(starts.withLock { $0 } == 1, "the cold upstream must run once and multicast, not once per collector")

        a.cancel()
        b.cancel()
        await a.value
        await b.value
    }

    // MARK: - StateFlow under concurrent writers

    @Test("StateFlow serializes concurrent writes and never loses the final value")
    func stateFlowConcurrentWritesConverge() async {
        let sentinel = 999_999
        let state = MutableStateFlow(-1)
        let observed = Mutex<[Int]>([])
        let collecting = Task {
            await state.asFlow().collect { value in observed.withLock { $0.append(value) } }
        }

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<8 {
                group.addTask {
                    for step in 0..<100 { await state.send(writer * 1000 + step) }
                }
            }
            await group.waitForAll()
        }
        // The last write wins because the actor serializes sends.
        await state.send(sentinel)

        while !observed.withLock({ $0.last == sentinel }) { await Task.yield() }
        #expect(await state.value == sentinel, "the final write must survive 800 concurrent writes")

        #expect(observed.withLock { $0.last } == sentinel)

        collecting.cancel()
        await collecting.value
    }

    // MARK: - SharedFlow replay ring-buffer overflow

    @Test("SharedFlow replays only the last N values when more than N were emitted")
    func sharedFlowReplayKeepsLastN() async {
        let shared = MutableSharedFlow<Int>(replay: 3)
        for value in 1...5 { await shared.emit(value) }

        let received = Mutex<[Int]>([])
        let collecting = Task {
            await shared.asFlow().collect { value in received.withLock { $0.append(value) } }
        }
        while received.withLock({ $0.count < 3 }) { await Task.yield() }

        #expect(received.withLock { $0 } == [3, 4, 5], "a late subscriber gets exactly the last 3 of 5 emitted")

        collecting.cancel()
        await collecting.value
    }
}
