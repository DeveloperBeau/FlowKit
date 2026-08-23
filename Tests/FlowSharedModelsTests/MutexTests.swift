import Testing
@testable import FlowSharedModels

@Suite("Mutex")
struct MutexTests {
    @Test("withLock returns the block's result")
    func withLockReturnsResult() {
        let mutex = Mutex(42)
        let result = mutex.withLock { value in
            value * 2
        }
        #expect(result == 84)
    }

    @Test("withLock can mutate the protected value")
    func withLockMutates() {
        let mutex = Mutex(0)
        mutex.withLock { value in
            value += 10
        }
        let current = mutex.withLock { $0 }
        #expect(current == 10)
    }

    @Test("concurrent access is serialized")
    func concurrentAccessIsSerialized() async {
        let mutex = Mutex(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    for _ in 0..<1_000 {
                        mutex.withLock { value in
                            value += 1
                        }
                    }
                }
            }
        }
        let final = mutex.withLock { $0 }
        #expect(final == 100_000)
    }

    @Test("Mutex is Sendable")
    func mutexIsSendable() async {
        let mutex = Mutex("hello")
        await Task.detached {
            mutex.withLock { value in
                value = "world"
            }
        }.value
        let final = mutex.withLock { $0 }
        #expect(final == "world")
    }

    @Test("lock is released when the body throws")
    func lockIsReleasedWhenBodyThrows() {
        let mutex = Mutex(1)
        do {
            try mutex.withLock { _ in
                throw FlowTestError.timeout
            }
            Issue.record("expected withLock to rethrow")
        } catch let error as FlowTestError {
            #expect(error == .timeout)
        } catch {
            Issue.record("expected FlowTestError, got \(error)")
        }

        mutex.withLock { $0 += 1 }
        #expect(mutex.withLock { $0 } == 2)
    }

    @Test("separate instances do not share state")
    func separateInstancesDoNotShareState() async {
        let a = Mutex(0)
        let b = Mutex(0)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    if index % 2 == 0 {
                        a.withLock { $0 += 1 }
                    } else {
                        b.withLock { $0 += 1 }
                    }
                }
            }
        }
        #expect(a.withLock { $0 } == 100)
        #expect(b.withLock { $0 } == 100)
    }

    @Test("concurrent sum is order independent")
    func concurrentSumIsOrderIndependent() async {
        for seed: UInt64 in [1, 2, 3] {
            var generator = LCGRandomNumberGenerator(seed: seed)
            let deltas = Array(1...1_000).shuffled(using: &generator)
            let mutex = Mutex(0)
            await withTaskGroup(of: Void.self) { group in
                for delta in deltas {
                    group.addTask {
                        mutex.withLock { $0 += delta }
                    }
                }
            }
            #expect(mutex.withLock { $0 } == 500_500)
        }
    }
}

/// A small deterministic generator so the fuzzed shuffle order is
/// reproducible across runs instead of depending on the system RNG.
private struct LCGRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 1
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}
