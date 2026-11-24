import Foundation
import Testing
import FlowCore
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

/// Publishes from a function that is not `async`, the way a delegate method or
/// a C callback does. It compiles only while `tryEmit` needs no `await`.
private func publish<S: Sequence<Int>>(_ values: S, into flow: MutableSharedFlow<Int>) {
    for value in values { flow.tryEmit(value) }
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

@Suite("MutableSharedFlow tryEmit", .timeLimit(.minutes(1)))
struct SharedFlowTryEmitTests {
    private static let fuzzSeed: UInt64 = 20_261_124

    @Test("10,000 tryEmit calls from one thread reach two subscribers in call order")
    func oneThreadKeepsCallOrderForTwoSubscribers() async throws {
        let shared = MutableSharedFlow<Int>()
        let first = Recorder<Int>()
        let second = Recorder<Int>()
        let firstCollecting = Task { await shared.asFlow().collect { first.record($0) } }
        let secondCollecting = Task { await shared.asFlow().collect { second.record($0) } }
        try await shared.waitForSubscribers(2)

        publish(1...10_000, into: shared)

        await first.wait(atLeast: 10_000)
        await second.wait(atLeast: 10_000)
        #expect(first.elements == Array(1...10_000))
        #expect(second.elements == Array(1...10_000))

        firstCollecting.cancel()
        secondCollecting.cancel()
        await firstCollecting.value
        await secondCollecting.value
    }

    @Test("A value sent with no subscriber and no replay is accepted and then lost")
    func valueWithoutSubscriberOrReplayIsLost() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0)

        #expect(shared.tryEmit(1), "the flow accepts a value that nobody is there to receive")
        #expect(await shared.replayCache.isEmpty)

        let received = Recorder<Int>()
        let collecting = Task { await shared.asFlow().collect { received.record($0) } }
        try await shared.waitForSubscribers(1)
        shared.tryEmit(2)

        await received.wait(atLeast: 1)
        #expect(received.elements == [2], "the value sent before the subscriber attached must not arrive")

        collecting.cancel()
        await collecting.value
    }

    @Test("With replay 1 a later subscriber receives the newest tryEmit value")
    func replayOneReachesLaterSubscriber() async throws {
        let shared = MutableSharedFlow<Int>(replay: 1)

        shared.tryEmit(1)
        shared.tryEmit(2)
        #expect(await shared.replayCache == [2])

        let received = Recorder<Int>()
        let collecting = Task { await shared.asFlow().collect { received.record($0) } }
        // The replay reaches the new subscriber before the next value is sent.
        await received.wait(atLeast: 1)
        shared.tryEmit(3)

        await received.wait(atLeast: 2)
        #expect(received.elements == [2, 3])

        collecting.cancel()
        await collecting.value
    }

    @Test("resetReplayCache drops the values tryEmit stored")
    func resetReplayCacheDropsTryEmitValues() async {
        let shared = MutableSharedFlow<Int>(replay: 2)
        publish([1, 2, 3], into: shared)
        #expect(await shared.replayCache == [2, 3])

        await shared.resetReplayCache()

        #expect(await shared.replayCache.isEmpty)
        shared.tryEmit(4)
        #expect(await shared.replayCache == [4])
    }

    @Test("dropOldest keeps the newest tryEmit value for a slow subscriber and never waits for it")
    func dropOldestKeepsNewestForSlowSubscriber() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0, extraBufferCapacity: 1, onBufferOverflow: .dropOldest)
        let release = Signal()
        let received = Recorder<Int>()
        let collecting = Task {
            await shared.asFlow().collect { value in
                await release.wait()
                received.record(value)
            }
        }
        try await shared.waitForSubscribers(1)

        // The subscriber is held, so a tryEmit that waited for it would never
        // return and the suite time limit would fail this test.
        publish(1...1000, into: shared)
        release.fire()

        await received.wait { $0.last == 1000 }
        let final = received.elements
        #expect(final.last == 1000, "dropOldest must keep the newest value")
        #expect(final.count <= 2, "a buffer of one must not deliver the whole burst")

        collecting.cancel()
        await collecting.value
    }

    @Test("dropLatest sheds the newest tryEmit values for a slow subscriber and still accepts them")
    func dropLatestShedsNewestForSlowSubscriber() async throws {
        let shared = MutableSharedFlow<Int>(replay: 0, extraBufferCapacity: 1, onBufferOverflow: .dropLatest)
        let release = Signal()
        let received = Recorder<Int>()
        let collecting = Task {
            await shared.asFlow().collect { value in
                await release.wait()
                received.record(value)
            }
        }
        try await shared.waitForSubscribers(1)

        publish(1...999, into: shared)
        #expect(shared.tryEmit(1000), "a value shed for one slow subscriber is still accepted by the flow")
        release.fire()

        await received.wait(atLeast: 1)
        let final = received.elements
        #expect(!final.contains(1000), "dropLatest must shed the newest value when the buffer is full")
        #expect(final.count <= 2, "a buffer of one must not deliver the whole burst")

        collecting.cancel()
        await collecting.value
    }

    @Test("Eight threads calling tryEmit at once lose nothing and keep each thread's own order")
    func concurrentThreadsLoseNothing() async throws {
        let threadCount = 8
        let perThread = 2000
        let shared = MutableSharedFlow<Int>(replay: 3)
        let received = Recorder<Int>()
        let finishedThreads = Recorder<Int>()
        let collecting = Task { await shared.asFlow().collect { received.record($0) } }
        try await shared.waitForSubscribers(1)

        // Thread `index` sends index * 10_000 + 0, 1, 2 and so on.
        for index in 0..<threadCount {
            Thread.detachNewThread {
                publish((0..<perThread).map { index * 10_000 + $0 }, into: shared)
                finishedThreads.record(index)
            }
        }

        await finishedThreads.wait(atLeast: threadCount)
        await received.wait(atLeast: threadCount * perThread)
        let all = received.elements
        #expect(all.count == 16_000)
        #expect(Set(all).count == 16_000, "no value may arrive twice")
        for index in 0..<threadCount {
            let fromThread = all.filter { $0 / 10_000 == index }
            #expect(fromThread == (0..<perThread).map { index * 10_000 + $0 }, "thread \(index) arrived out of order")
        }
        // The replay is the tail of the same order the subscriber saw.
        #expect(await shared.replayCache == Array(all.suffix(3)))

        collecting.cancel()
        await collecting.value
    }

    @Test("tryEmit from a cancelled task still publishes")
    func cancelledCallerStillPublishes() async {
        let shared = MutableSharedFlow<Int>(replay: 1)

        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return (Task.isCancelled, shared.tryEmit(7))
        }

        let (wasCancelled, wasAccepted) = await caller.value
        #expect(wasCancelled)
        #expect(wasAccepted)
        #expect(await shared.replayCache == [7])
    }

    @Test("A subscriber that left receives nothing more and tryEmit still accepts")
    func departedSubscriberReceivesNothingMore() async throws {
        let shared = MutableSharedFlow<Int>(replay: 1)
        let received = Recorder<Int>()
        let collecting = Task { await shared.asFlow().collect { received.record($0) } }
        try await shared.waitForSubscribers(1)
        shared.tryEmit(1)
        await received.wait(atLeast: 1)

        collecting.cancel()
        await collecting.value
        try await shared.waitForSubscribers(atMost: 0)

        #expect(shared.tryEmit(2))
        #expect(received.elements == [1])
        #expect(await shared.replayCache == [2])
    }

    @Test("An empty element and a one megabyte element arrive intact")
    func emptyAndHugeElementsArriveIntact() async throws {
        let shared = MutableSharedFlow<[UInt8]>(replay: 2)
        var huge = [UInt8](repeating: 0xAB, count: 1_000_000)
        huge[0] = 0x01
        huge[999_999] = 0x02

        shared.tryEmit([])
        shared.tryEmit(huge)

        let received = Recorder<[UInt8]>()
        let collecting = Task { await shared.asFlow().collect { received.record($0) } }
        await received.wait(atLeast: 2)
        let elements = received.elements
        try #require(elements.count == 2)
        #expect(elements[0].isEmpty)
        #expect(elements[1].count == 1_000_000)
        #expect(elements[1].first == 0x01)
        #expect(elements[1].last == 0x02)
        #expect(elements[1].dropFirst().dropLast().allSatisfy { $0 == 0xAB })

        collecting.cancel()
        await collecting.value
    }

    @Test("A tryEmit right after a collector attaches arrives once, after the replay")
    func valueSentWhileCollectorReadsReplayArrivesOnce() async throws {
        for round in 0..<500 {
            let shared = MutableSharedFlow<Int>(replay: 2)
            shared.tryEmit(1)
            shared.tryEmit(2)
            let received = Recorder<Int>()
            let collecting = Task { await shared.asFlow().collect { received.record($0) } }
            try await shared.waitForSubscribers(1)

            shared.tryEmit(3)
            shared.tryEmit(-1)

            await received.wait { $0.last == -1 }
            #expect(received.elements == [1, 2, 3, -1], "round \(round)")

            collecting.cancel()
            await collecting.value
        }
    }

    @Test("Seeded fuzz: emit and tryEmit mixed from one task keep order and fill the replay")
    func seededFuzzMixedEmitAndTryEmit() async throws {
        print("MutableSharedFlow tryEmit fuzz seed: \(Self.fuzzSeed)")
        var generator = SplitMix64(state: Self.fuzzSeed)

        for round in 0..<200 {
            let replay = Int.random(in: 0...4, using: &generator)
            let count = Int.random(in: 0...40, using: &generator)
            let shared = MutableSharedFlow<Int>(replay: replay)
            let received = Recorder<Int>()
            let collecting = Task { await shared.asFlow().collect { received.record($0) } }
            try await shared.waitForSubscribers(1)

            // The values are 1...count, then -1 to mark the end of the round.
            var sent: [Int] = []
            for value in stride(from: 1, through: count, by: 1) {
                if Bool.random(using: &generator) {
                    shared.tryEmit(value)
                } else {
                    await shared.emit(value)
                }
                sent.append(value)
            }
            shared.tryEmit(-1)
            sent.append(-1)

            await received.wait { $0.last == -1 }
            #expect(received.elements == sent, "round \(round): replay \(replay), count \(count)")
            #expect(await shared.replayCache == Array(sent.suffix(replay)), "round \(round): replay \(replay), count \(count)")

            let late = Recorder<Int>()
            let lateCollecting = Task { await shared.asFlow().collect { late.record($0) } }
            try await shared.waitForSubscribers(2)
            // The replay reaches the late subscriber before the next value is sent.
            await late.wait(atLeast: min(replay, sent.count))
            shared.tryEmit(-2)
            await late.wait { $0.last == -2 }
            #expect(late.elements == Array(sent.suffix(replay)) + [-2], "round \(round): late subscriber")

            collecting.cancel()
            lateCollecting.cancel()
            await collecting.value
            await lateCollecting.value
        }
    }
}
