import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("Flow.asAsyncStream bridge")
struct AsyncStreamBridgeTests {
    @Test("asAsyncStream yields all values from a finite flow")
    func yieldsAllValues() async {
        let flow = Flow(of: 1, 2, 3)
        let stream = flow.asAsyncStream()
        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test("asAsyncStream finishes when the flow completes")
    func finishesOnCompletion() async {
        let flow = Flow<String>.empty
        let stream = flow.asAsyncStream()
        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    @Test("asAsyncStream cancels collection when the stream is cancelled")
    func cancelsOnStreamCancellation() async {
        let wasCancelled = Mutex(false)
        let flow = Flow<Int> { _ in
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    await Task.yield()
                }
            } onCancel: {
                wasCancelled.withLock { $0 = true }
            }
        }

        let task = Task {
            let stream = flow.asAsyncStream()
            for await _ in stream { break }
        }

        try? await Task.sleep(for: .seconds(0.01))
        task.cancel()
        await task.value

        #expect(wasCancelled.withLock { $0 })
    }

    @Test("asAsyncThrowingStream yields all values from a finite throwing flow")
    func throwingYieldsAllValues() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        let stream = flow.asAsyncThrowingStream()
        var received: [Int] = []
        for try await value in stream {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test("asAsyncThrowingStream propagates errors")
    func throwingPropagatesErrors() async {
        struct BridgeError: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw BridgeError()
        }
        let stream = flow.asAsyncThrowingStream()
        var received: [Int] = []
        do {
            for try await value in stream {
                received.append(value)
            }
            Issue.record("expected error")
        } catch is BridgeError {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(received == [1])
    }

    @Test("asAsyncThrowingStream cancels collection on stream cancellation")
    func throwingCancelsCollection() async {
        let wasCancelled = Mutex(false)
        let flow = ThrowingFlow<Int> { _ in
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    await Task.yield()
                }
            } onCancel: {
                wasCancelled.withLock { $0 = true }
            }
        }

        let task = Task {
            let stream = flow.asAsyncThrowingStream()
            do {
                for try await _ in stream { break }
            } catch {}
        }

        try? await Task.sleep(for: .seconds(0.01))
        task.cancel()
        await task.value

        #expect(wasCancelled.withLock { $0 })
    }
}
