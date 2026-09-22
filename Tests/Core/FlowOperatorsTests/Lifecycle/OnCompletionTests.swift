import Testing
import FlowCore
import FlowTesting
import FlowSharedModels
@testable import FlowOperators

@Suite("onCompletion operator")
struct OnCompletionTests {
    @Test("onCompletion runs with nil error on normal completion")
    func normalCompletion() async throws {
        let captured = Mutex<Bool?>(nil)

        let flow = Flow(of: 1, 2)
        try await flow.onCompletion { error in
            captured.withLock { $0 = (error == nil) }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectCompletion()
        }

        #expect(captured.withLock { $0 } == true)
    }

    @Test("onCompletion on ThrowingFlow receives the error")
    func throwingCompletion() async throws {
        struct BoomError: Error, Equatable {}
        let capturedError = Mutex<Bool>(false)

        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BoomError()
        }

        try await flow.onCompletion { error in
            capturedError.withLock { $0 = (error != nil) }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectError(BoomError())
        }

        #expect(capturedError.withLock { $0 } == true)
    }
}
