import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("ThrowingFlow")
struct ThrowingFlowTests {
    @Test("collect invokes the body closure with a ThrowingCollector")
    func collectInvokesBody() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            try await collector.emit(2)
            try await collector.emit(3)
        }
        let storage = Mutex<[Int]>([])
        try await flow.collect { value in
            storage.withLock { $0.append(value) }
        }
        let received = storage.withLock { $0 }
        #expect(received == [1, 2, 3])
    }

    @Test("collect propagates errors from the flow body")
    func collectPropagatesErrors() async {
        struct DatabaseError: Error, Equatable {}
        let flow = ThrowingFlow<String> { collector in
            try await collector.emit("first")
            throw DatabaseError()
        }
        let storage = Mutex<[String]>([])
        await #expect(throws: DatabaseError.self) {
            try await flow.collect { value in
                storage.withLock { $0.append(value) }
            }
        }
        let received = storage.withLock { $0 }
        #expect(received == ["first"])
    }

    @Test("collect propagates errors from the downstream action")
    func collectPropagatesDownstreamErrors() async {
        struct RenderError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            try await collector.emit(2)
            try await collector.emit(3)
        }
        await #expect(throws: RenderError.self) {
            try await flow.collect { value in
                if value == 2 { throw RenderError() }
            }
        }
    }

    @Test("ThrowingFlow is Sendable")
    func isSendable() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(42)
        }
        let storage = Mutex(0)
        let received: Int = try await Task.detached {
            try await flow.collect { value in
                storage.withLock { $0 = value }
            }
            return storage.withLock { $0 }
        }.value
        #expect(received == 42)
    }
}
