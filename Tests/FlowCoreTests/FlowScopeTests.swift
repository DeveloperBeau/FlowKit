import Testing
import Foundation
import FlowSharedModels
import FlowTestingCore
@testable import FlowCore

@Suite("FlowScope")
struct FlowScopeTests {
    @Test("launch runs the provided work")
    func launchRunsWork() async {
        let scope = FlowScope()
        let ran = Mutex(false)
        let task = scope.launch {
            ran.withLock { $0 = true }
        }
        await task.value
        #expect(ran.withLock { $0 })
    }

    @Test("cancel cancels all running tasks")
    func cancelCancelsTasks() async {
        let scope = FlowScope()
        let wasCancelled = Mutex(false)
        let started = Mutex(false)

        // Observe cancellation by exiting the spin: a cancel that races
        // withTaskCancellationHandler's registration can be missed by the
        // runtime, whereas the isCancelled flag is always visible.
        let task = scope.launch {
            started.withLock { $0 = true }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
            }
            wasCancelled.withLock { $0 = true }
        }

        // Wait until the task is actually running before cancelling, rather than
        // racing a fixed sleep against it.
        await waitUntil { started.withLock { $0 } }

        scope.cancel()
        await task.value

        #expect(wasCancelled.withLock { $0 })
    }

    @Test("completed tasks are removed from the scope")
    func completedTasksRemoved() async {
        let scope = FlowScope()
        for _ in 0..<5 {
            let task = scope.launch {
                // Completes immediately
            }
            await task.value
        }
        // Self-removal runs inside the Task after work() returns.
        // Give the executor time to run the removal closures.
        for _ in 0..<10 {
            if scope.activeTaskCount == 0 { break }
            try? await Task.sleep(for: .seconds(0.005))
        }
        #expect(scope.activeTaskCount == 0)
    }

    @Test("launch after cancel produces a cancelled task")
    func launchAfterCancel() async {
        let scope = FlowScope()
        scope.cancel()
        let task = scope.launch {
            // Should never actually run meaningful work
        }
        await task.value
        #expect(task.isCancelled)
    }

    @Test("deinit cancels pending tasks")
    func deinitCancels() async {
        let wasCancelled = Mutex(false)
        let started = Mutex(false)

        do {
            let scope = FlowScope()
            // Observe cancellation by exiting the spin: a cancel that races
            // withTaskCancellationHandler's registration can be missed by the
            // runtime, whereas the isCancelled flag is always visible.
            _ = scope.launch {
                started.withLock { $0 = true }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                wasCancelled.withLock { $0 = true }
            }
            // Ensure the task is running before the scope deinits.
            await waitUntil { started.withLock { $0 } }
        }

        // Converge on deinit's cancellation reaching the task, bounded so a
        // genuine regression fails instead of hanging the suite.
        await waitUntil { wasCancelled.withLock { $0 } }
        #expect(wasCancelled.withLock { $0 })
    }
}
