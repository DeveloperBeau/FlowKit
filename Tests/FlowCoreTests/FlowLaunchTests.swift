import Testing
import FlowSharedModels
import FlowTestingCore
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
                try? await Task.sleep(for: .milliseconds(1))
            }
        }

        _ = flow.launch(in: scope)

        // launch registers the task synchronously before returning, so the count
        // is already 1 here — no need to sleep and race it.
        #expect(scope.activeTaskCount == 1)
        scope.cancel()
    }

    @Test("cancelling the scope cancels the launched flow")
    func cancellingScopeCancelsFlow() async {
        let scope = FlowScope()
        let wasCancelled = Mutex(false)
        let started = Mutex(false)

        // Observe cancellation by exiting the spin: a cancel that races
        // withTaskCancellationHandler's registration can be missed by the
        // runtime, whereas the isCancelled flag is always visible.
        let flow = Flow<Int> { _ in
            started.withLock { $0 = true }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            wasCancelled.withLock { $0 = true }
        }

        let task = flow.launch(in: scope)
        // Cancel a running task, not a not-yet-started one.
        await waitUntil { started.withLock { $0 } }
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
