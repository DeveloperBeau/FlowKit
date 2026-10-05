import Testing
import FlowCore
import FlowSharedModels
import FlowTestSupport
@testable import FlowHotStreams

/// A one-shot gate: `wait()` suspends until `open()` is called once, after
/// which every wait passes. Holds a subscriber inside its collect action while
/// the source floods it, making per-subscriber buffering deterministic.
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

@Suite("SharedFlow subscriber backpressure")
struct SharedFlowBackpressureTests {
    @Test("dropOldest bounds a slow subscriber's buffer and keeps the newest value")
    func dropOldestConflatesForSlowSubscriber() async {
        let shared = MutableSharedFlow<Int>(replay: 0, extraBufferCapacity: 1, onBufferOverflow: .dropOldest)
        let gate = Gate()
        let received = Recorder<Int>()

        let collecting = Task {
            await shared.asFlow().collect { value in
                await gate.wait()
                received.record(value)
            }
        }
        await pollUntil { await shared.subscriptionCount >= 1 }

        // If the emitter suspended on a full subscriber buffer, this would
        // deadlock; under dropOldest it drops and never suspends.
        for value in 1...1000 { await shared.emit(value) }
        await gate.open()

        await received.wait { $0.last == 1000 }
        let final = received.elements
        #expect(final.last == 1000, "dropOldest must keep the newest value")
        #expect(final.count <= 2, "a cap-1 subscriber buffer must conflate a flood of 1000, not deliver them all")

        collecting.cancel()
        await collecting.value
    }

    @Test("dropLatest bounds a slow subscriber's buffer and sheds the newest values")
    func dropLatestShedsForSlowSubscriber() async {
        let shared = MutableSharedFlow<Int>(replay: 0, extraBufferCapacity: 1, onBufferOverflow: .dropLatest)
        let gate = Gate()
        let received = Recorder<Int>()

        let collecting = Task {
            await shared.asFlow().collect { value in
                await gate.wait()
                received.record(value)
            }
        }
        await pollUntil { await shared.subscriptionCount >= 1 }

        for value in 1...1000 { await shared.emit(value) }
        await gate.open()

        // Wait for the first drained value to land.
        await received.wait(atLeast: 1)
        let final = received.elements
        #expect(!final.contains(1000), "dropLatest must shed the newest values when the buffer is full")
        #expect(final.count <= 2, "a cap-1 subscriber buffer must not deliver all 1000")

        collecting.cancel()
        await collecting.value
    }

    @Test("The default (suspend, no extra capacity) still delivers every value in order")
    func defaultIsLossless() async {
        let shared = MutableSharedFlow<Int>(replay: 0)
        let received = Recorder<Int>()
        let collecting = Task {
            await shared.asFlow().collect { value in received.record(value) }
        }
        await pollUntil { await shared.subscriptionCount >= 1 }

        for value in 1...100 { await shared.emit(value) }
        await received.wait(atLeast: 100)
        #expect(received.elements == Array(1...100), "the default policy must not drop or reorder")

        collecting.cancel()
        await collecting.value
    }
}
