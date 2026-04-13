import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("retry operators")
struct RetryTests {
    @Test("retry re-executes the flow body on error")
    func retryReExecutes() async throws {
        let attempts = Mutex(0)
        let flow = ThrowingFlow<Int> { collector in
            let attempt = attempts.withLock { a -> Int in a += 1; return a }
            if attempt < 3 {
                try await collector.emit(attempt)
                throw RetryTestError(attempt: attempt)
            }
            try await collector.emit(attempt)
        }

        try await flow.retry(3).test { tester in
            // Attempt 1: emits 1, then throws
            try await tester.expectValue(1)
            // Attempt 2: emits 2, then throws
            try await tester.expectValue(2)
            // Attempt 3: emits 3, completes normally
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("retry exhaustion propagates the error")
    func retryExhaustion() async throws {
        struct PermanentError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in
            throw PermanentError()
        }

        try await flow.retry(2).test { tester in
            try await tester.expectError(PermanentError())
        }
    }

    @Test("retry with shouldRetry predicate skips non-retryable errors")
    func retryWithPredicate() async throws {
        struct RetryableError: Error, Equatable {}
        struct FatalError: Error, Equatable {}

        let attempts = Mutex(0)
        let flow = ThrowingFlow<Int> { _ in
            let attempt = attempts.withLock { a -> Int in a += 1; return a }
            if attempt == 1 { throw FatalError() }
            throw RetryableError()
        }

        try await flow.retry(5, shouldRetry: { $0 is RetryableError }).test { tester in
            // First attempt throws FatalError which doesn't match predicate
            try await tester.expectError(FatalError())
        }
    }

    @Test("retryWhen uses async predicate with attempt count")
    func retryWhen() async throws {
        let attempts = Mutex(0)
        let flow = ThrowingFlow<String> { collector in
            let attempt = attempts.withLock { a -> Int in a += 1; return a }
            if attempt <= 2 {
                throw RetryTestError(attempt: attempt)
            }
            try await collector.emit("success")
        }

        try await flow.retryWhen { _, attempt in
            attempt < 3  // allow up to 2 retries
        }.test { tester in
            try await tester.expectValue("success")
            try await tester.expectCompletion()
        }
    }

    @Test("retryWhen stops retrying when predicate returns false")
    func retryWhenStops() async throws {
        struct StopError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { _ in
            throw StopError()
        }

        try await flow.retryWhen { _, attempt in
            attempt < 2
        }.test { tester in
            try await tester.expectError(StopError())
        }
    }
}

struct RetryTestError: Error, Equatable {
    let attempt: Int
}
