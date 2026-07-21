import Testing
import FlowCore
import FlowHotStreams
import FlowTesting

@Suite("MutableStateFlow atomics")
struct StateFlowAtomicsTests {
    @Test("getAndUpdate returns the previous value and applies the update")
    func getAndUpdate() async {
        let state = MutableStateFlow(10)
        let previous = await state.getAndUpdate { $0 + 5 }
        #expect(previous == 10)
        #expect(await state.value == 15)
    }

    @Test("updateAndGet returns the new value")
    func updateAndGet() async {
        let state = MutableStateFlow(10)
        let next = await state.updateAndGet { $0 * 2 }
        #expect(next == 20)
        #expect(await state.value == 20)
    }

    @Test("compareAndSet swaps only when the expectation matches")
    func compareAndSet() async {
        let state = MutableStateFlow("a")
        #expect(await state.compareAndSet(expected: "a", newValue: "b"))
        #expect(await state.value == "b")
        #expect(await !state.compareAndSet(expected: "a", newValue: "c"))
        #expect(await state.value == "b")
    }

    @Test("100 concurrent getAndUpdate increments lose no updates")
    func concurrentIncrements() async {
        let state = MutableStateFlow(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { await state.getAndUpdate { $0 + 1 } }
            }
        }
        #expect(await state.value == 100)
    }
}

@Suite("MutableSharedFlow replayCache")
struct ReplayCacheTests {
    @Test("replayCache exposes the values a new subscriber would receive")
    func exposesReplayedValues() async {
        let shared = MutableSharedFlow<Int>(replay: 2)
        await shared.emit(1)
        await shared.emit(2)
        await shared.emit(3)
        #expect(await shared.replayCache == [2, 3])
    }

    @Test("replayCache is empty with replay zero and after a reset")
    func emptyWithoutReplay() async {
        let none = MutableSharedFlow<Int>(replay: 0)
        await none.emit(1)
        #expect(await none.replayCache == [])

        let some = MutableSharedFlow<Int>(replay: 2)
        await some.emit(1)
        await some.resetReplayCache()
        #expect(await some.replayCache == [])
    }
}
