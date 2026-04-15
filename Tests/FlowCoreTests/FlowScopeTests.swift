import Testing
import Foundation
import FlowSharedModels
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

        let task = scope.launch {
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    await Task.yield()
                }
            } onCancel: {
                wasCancelled.withLock { $0 = true }
            }
        }

        // Give the task a moment to start
        try? await Task.sleep(for: .seconds(0.005))

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

        do {
            let scope = FlowScope()
            _ = scope.launch {
                await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                } onCancel: {
                    wasCancelled.withLock { $0 = true }
                }
            }
            try? await Task.sleep(for: .seconds(0.005))
        }

        // Give time for deinit to propagate cancellation
        try? await Task.sleep(for: .seconds(0.05))
        #expect(wasCancelled.withLock { $0 })
    }
}
