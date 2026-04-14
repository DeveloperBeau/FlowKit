import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("catch operator")
struct CatchTests {
    @Test("catch converts ThrowingFlow to Flow by handling errors")
    func catchConvertsToFlow() async throws {
        struct FetchError: Error, Equatable {}
        let flow = ThrowingFlow<String> { collector in
            try await collector.emit("first")
            throw FetchError()
        }
        try await flow.catch { error, collector in
            await collector.emit("fallback")
        }.test { tester in
            try await tester.expectValue("first")
            try await tester.expectValue("fallback")
            try await tester.expectCompletion()
        }
    }

    @Test("catch handler can emit multiple recovery values")
    func multipleRecoveryValues() async throws {
        struct LoadError: Error {}
        let flow = ThrowingFlow<Int> { _ in throw LoadError() }
        try await flow.catch { _, collector in
            await collector.emit(-1)
            await collector.emit(-2)
        }.test { tester in
            try await tester.expectValue(-1)
            try await tester.expectValue(-2)
            try await tester.expectCompletion()
        }
    }

    @Test("catch handler that emits nothing produces values-then-completion")
    func emptyRecovery() async throws {
        struct Boom: Error {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Boom()
        }
        try await flow.catch { _, _ in
            // Emit nothing. Just swallow the error.
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectCompletion()
        }
    }

    @Test("catch is not called when flow completes normally")
    func notCalledOnNormalCompletion() async throws {
        let catchCalled = Mutex(false)
        let flow = ThrowingFlow(of: 1, 2, 3)
        try await flow.catch { _, _ in
            catchCalled.withLock { $0 = true }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
        #expect(!catchCalled.withLock { $0 })
    }
}
