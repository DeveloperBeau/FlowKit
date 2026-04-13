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
                    mutex.withLock { value in
                        value += 1
                    }
                }
            }
        }
        let final = mutex.withLock { $0 }
        #expect(final == 100)
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
}
