import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowOperators

/// Operators that need only part of a flow must return once they have it and
/// cancel the producer, even when the producer never completes on its own.
/// Each open flow below emits and then parks on `awaitClose`, so an operator
/// that waits for completion hits the timeout instead of returning.
@Suite("short-circuiting operators cancel an open flow")
struct ShortCircuitTests {
    /// A callback flow that sends `values`, then stays open until it is torn
    /// down, and fires `tornDown` from its teardown.
    private func openFlow(_ values: Int..., tornDown: Signal) -> Flow<Int> {
        Flow<Int>.callbackFlow { scope in
            for value in values { scope.trySend(value) }
            await scope.awaitClose { tornDown.fire() }
        }
    }

    @Test("first returns the first value of an open flow and tears the producer down")
    func firstOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(7, 8, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.first() }
        #expect(result == 7)
        #expect(tornDown.hasFired)
    }

    @Test("first returns the first value of a plain flow that parks after it")
    func firstOnParkedFlow() async throws {
        let cancelled = Signal()
        let flow = Flow<Int> { collector in
            await collector.emit(1)
            await parkUntilCancelled()
            if Task.isCancelled { cancelled.fire() }
        }
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.first() }
        #expect(result == 1)
        #expect(cancelled.hasFired)
    }

    @Test("first returns nil for a flow that completes without emitting")
    func firstOnEmptyFlow() async throws {
        let result = try await withThrowingTimeout(.seconds(30)) { await Flow<Int>.empty.first() }
        #expect(result == nil)
    }

    @Test("first on a silent open flow returns nil once the caller cancels")
    func firstOnSilentFlowEndsOnCancel() async throws {
        let tornDown = Signal()
        let flow = openFlow(tornDown: tornDown)
        let task = Task { await flow.first() }
        task.cancel()
        let result = try await withThrowingTimeout(.seconds(30)) { await task.value }
        #expect(result == nil)
        #expect(tornDown.hasFired)
    }

    @Test("first(where:) returns the first match of an open flow and tears the producer down")
    func firstWhereOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(1, 2, 3, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.first(where: { $0 > 1 }) }
        #expect(result == 2)
        #expect(tornDown.hasFired)
    }

    @Test("contains returns true on a match in an open flow")
    func containsOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(1, 2, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.contains(where: { $0 == 2 }) }
        #expect(result)
        #expect(tornDown.hasFired)
    }

    @Test("allSatisfy returns false on the first failing value of an open flow")
    func allSatisfyOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(2, 3, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.allSatisfy { $0.isMultiple(of: 2) } }
        #expect(!result)
        #expect(tornDown.hasFired)
    }

    @Test("prefix(1).toArray completes on an open flow and tears the producer down")
    func prefixOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(4, 5, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.prefix(1).toArray() }
        #expect(result == [4])
        #expect(tornDown.hasFired)
    }

    @Test("prefix(while:).toArray completes on an open flow at the first failing value")
    func prefixWhileOnOpenFlow() async throws {
        let tornDown = Signal()
        let flow = openFlow(1, 2, 9, tornDown: tornDown)
        let result = try await withThrowingTimeout(.seconds(30)) { await flow.prefix(while: { $0 < 3 }).toArray() }
        #expect(result == [1, 2])
        #expect(tornDown.hasFired)
    }

    @Test("ThrowingFlow prefix(1) completes on an open flow without a cancellation error")
    func throwingPrefixOnOpenFlow() async throws {
        let cancelled = Signal()
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            do {
                try await Task.sleep(for: .seconds(1 << 40))
            } catch {
                cancelled.fire()
                throw error
            }
        }
        let received = Mutex<[Int]>([])
        try await withThrowingTimeout(.seconds(30)) {
            try await flow.prefix(1).collect { value in received.withLock { $0.append(value) } }
        }
        #expect(received.withLock { $0 } == [1])
        #expect(cancelled.hasFired)
    }

    @Test("ThrowingFlow prefix(while:) completes on an open flow without a cancellation error")
    func throwingPrefixWhileOnOpenFlow() async throws {
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            try await collector.emit(5)
            try await Task.sleep(for: .seconds(1 << 40))
        }
        let received = Mutex<[Int]>([])
        try await withThrowingTimeout(.seconds(30)) {
            try await flow.prefix(while: { $0 < 3 }).collect { value in received.withLock { $0.append(value) } }
        }
        #expect(received.withLock { $0 } == [1])
    }

    @Test("ThrowingFlow prefix still forwards an upstream error thrown before the stop")
    func throwingPrefixForwardsEarlyError() async throws {
        struct Boom: Error {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Boom()
        }
        await #expect(throws: Boom.self) {
            try await flow.prefix(2).collect { _ in }
        }
    }
}
