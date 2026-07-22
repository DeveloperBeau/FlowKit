import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowHotStreams

/// A value written by one identified writer; used to check that concurrent
/// writers never produce torn or out-of-program-order observations.
private struct WriterStamp: Sendable, Equatable {
    let writer: Int
    let iteration: Int
}

@Suite("MutableStateFlow synchronous value")
struct StateFlowSyncValueTests {
    // MARK: - Success

    @Test("synchronous set followed by synchronous get returns the value")
    func syncSetThenGet() {
        let state = MutableStateFlow(0)
        state.value = 42
        #expect(state.value == 42)

        state.send(7)
        #expect(state.value == 7)

        state.update { $0 * 2 }
        #expect(state.value == 14)
    }

    @Test("collectors observe values set synchronously, ending with the latest")
    func collectorsSeeLatest() async throws {
        let state = MutableStateFlow(0)
        try await state.asFlow().test { tester in
            try await tester.expectValue(0)
            state.value = 1
            try await tester.expectValue(1)
            state.value = 2
            try await tester.expectValue(2)
        }
        #expect(state.value == 2)
    }

    @Test("setting an equal value is a no-op (deduplication preserved)")
    func equalSetIsNoOp() async throws {
        let state = MutableStateFlow(5)
        try await state.asFlow().test { tester in
            try await tester.expectValue(5)
            state.value = 5
            await tester.expectNoValue(within: .milliseconds(100))
            state.value = 6
            try await tester.expectValue(6)
        }
    }

    @Test("synchronous atomics: getAndUpdate, updateAndGet, compareAndSet")
    func syncAtomics() {
        let state = MutableStateFlow(10)
        #expect(state.getAndUpdate { $0 + 1 } == 10)
        #expect(state.value == 11)
        #expect(state.updateAndGet { $0 + 1 } == 12)
        #expect(state.compareAndSet(expected: 12, newValue: 20))
        #expect(!state.compareAndSet(expected: 12, newValue: 30))
        #expect(state.value == 20)
    }

    // MARK: - Misuse

    @Test("setting the value from inside a collector callback does not deadlock")
    func setFromCollectorCallbackDoesNotDeadlock() async {
        let state = MutableStateFlow(0)
        let observed = Mutex<[Int]>([])

        let collector = Task {
            await state.asFlow().collect { value in
                observed.withLock { $0.append(value) }
                if value == 1 {
                    // A synchronous re-entrant set while the delivery that
                    // carried `1` is still being processed.
                    state.value = 2
                }
            }
        }

        // Only set after the collector has replayed the initial value, so the
        // observed sequence is fully determined.
        await waitUntil { !observed.withLock { $0 }.isEmpty }
        state.value = 1
        await waitUntil { observed.withLock { $0 }.contains(2) }
        #expect(observed.withLock { $0 } == [0, 1, 2], "the re-entrant set is delivered after the current one")
        #expect(state.value == 2)
        collector.cancel()
    }

    // MARK: - Fuzz / adversarial

    @Test("multi-thread set storm: no torn reads, per-writer monotonic order, convergence")
    func multiThreadSetStorm() async {
        let writers = 8
        let iterations = 200
        let initial = WriterStamp(writer: -1, iteration: 0)
        let state = MutableStateFlow(initial)

        let observed = Mutex<[WriterStamp]>([])
        let collector = Task {
            await state.asFlow().collect { value in
                observed.withLock { $0.append(value) }
            }
        }
        await waitUntil { !observed.withLock { $0 }.isEmpty }

        // Concurrent writers hammer the value from multiple threads; reader
        // tasks pull the sync getter the whole time.
        let readerSawInvalid = Mutex(false)
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    for iteration in 1...iterations {
                        state.value = WriterStamp(writer: writer, iteration: iteration)
                    }
                }
            }
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<500 {
                        let snapshot = state.value
                        let valid = snapshot == initial
                            || ((0..<writers).contains(snapshot.writer)
                                && (1...iterations).contains(snapshot.iteration))
                        if !valid { readerSawInvalid.withLock { $0 = true } }
                        await Task.yield()
                    }
                }
            }
        }
        #expect(!readerSawInvalid.withLock { $0 }, "a synchronous get must never observe a torn value")

        // Deterministic convergence point after the storm.
        let final = WriterStamp(writer: 99, iteration: 1)
        state.value = final
        await waitUntil { observed.withLock { $0 }.last == final }
        #expect(state.value == final)
        #expect(observed.withLock { $0 }.last == final, "collectors converge on the final value")

        // Program order per writer: for any single writer, observed
        // iterations must strictly increase (conflation may skip, never
        // reorder or repeat).
        let sequence = observed.withLock { $0 }
        for writer in 0..<writers {
            let iterationsSeen = sequence.filter { $0.writer == writer }.map(\.iteration)
            let monotonic = zip(iterationsSeen, iterationsSeen.dropFirst()).allSatisfy { $0 < $1 }
            #expect(monotonic, "writer \(writer)'s observed values must follow its program order")
        }

        collector.cancel()
    }
}
