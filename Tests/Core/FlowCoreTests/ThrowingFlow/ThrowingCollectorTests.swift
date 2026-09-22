import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("ThrowingCollector")
struct ThrowingCollectorTests {
    @Test("emit forwards value to the action closure")
    func emitForwardsValue() async throws {
        let storage = Mutex<[Int]>([])
        let collector = ThrowingCollector<Int> { value in
            storage.withLock { $0.append(value) }
        }
        try await collector.emit(1)
        try await collector.emit(2)
        try await collector.emit(3)
        let received = storage.withLock { $0 }
        #expect(received == [1, 2, 3])
    }

    @Test("emit propagates errors from the action")
    func emitPropagatesErrors() async {
        struct TestError: Error, Equatable {}
        let collector = ThrowingCollector<String> { _ in
            throw TestError()
        }
        await #expect(throws: TestError.self) {
            try await collector.emit("hello")
        }
    }

    @Test("ThrowingCollector is Sendable")
    func isSendable() async throws {
        let storage = Mutex<[Int]>([])
        let collector = ThrowingCollector<Int> { value in
            storage.withLock { $0.append(value) }
        }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? await collector.emit(i)
                }
            }
        }
        let final = storage.withLock { $0.sorted() }
        #expect(final == Array(0..<10))
    }
}
