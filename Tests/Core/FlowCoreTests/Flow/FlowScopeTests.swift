import Testing
import FlowTestSupport
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
        let wasCancelled = Signal()
        let started = Signal()

        let task = scope.launch {
            started.fire()
            await parkUntilCancelled()
            wasCancelled.fire()
        }

        // Cancel a running task, not a not-yet-started one.
        await started.wait()

        scope.cancel()
        await task.value

        #expect(wasCancelled.hasFired)
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
        // Self-removal is the last step of the task's closure, so a finished
        // task is already out of the scope.
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
        let wasCancelled = Signal()
        let started = Signal()

        do {
            let scope = FlowScope()
            _ = scope.launch {
                started.fire()
                await parkUntilCancelled()
                wasCancelled.fire()
            }
            // Ensure the task is running before the scope deinits.
            await started.wait()
        }

        // The scope is gone; its deinit must have cancelled the parked task.
        await wasCancelled.wait()
        #expect(wasCancelled.hasFired)
    }
}
