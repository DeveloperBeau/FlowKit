import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("Flow.launch(in:)")
struct FlowLaunchTests {
    @Test("launch(in:) starts collection in the scope and returns a Task")
    func launchStartsCollection() async {
        let scope = FlowScope()
        let received = Mutex<[Int]>([])

        let sideEffectFlow = Flow<Int> { collector in
            await collector.emit(1)
            received.withLock { $0.append(1) }
            await collector.emit(2)
            received.withLock { $0.append(2) }
            await collector.emit(3)
            received.withLock { $0.append(3) }
        }

        let task = sideEffectFlow.launch(in: scope)
        await task.value

        #expect(received.withLock { $0 } == [1, 2, 3])
    }

    @Test("launch(in:) task is tracked in the scope")
    func launchTaskIsTracked() async {
        let scope = FlowScope()
        let flow = Flow<Int> { _ in
            // Suspend forever until cancelled
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        _ = flow.launch(in: scope)

        // Give the launch a moment to register
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(scope.activeTaskCount == 1)
        scope.cancel()
    }

    @Test("cancelling the scope cancels the launched flow")
    func cancellingScopeCancelsFlow() async {
        let scope = FlowScope()
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

        let task = flow.launch(in: scope)
        try? await Task.sleep(nanoseconds: 5_000_000)
        scope.cancel()
        await task.value

        #expect(wasCancelled.withLock { $0 })
    }

    @Test("ThrowingFlow.launch(in:) starts collection and swallows errors")
    func throwingLaunchSwallowsErrors() async {
        let scope = FlowScope()
        let received = Mutex<[Int]>([])

        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            try await collector.emit(2)
            received.withLock { $0 = [1, 2] }
            throw CancellationError()
        }

        let task = flow.launch(in: scope)
        await task.value

        #expect(received.withLock { $0 } == [1, 2])
    }
}
