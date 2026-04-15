import Testing
import Foundation
import FlowSharedModels
@testable import FlowCore

@Suite("Memory safety")
struct MemoryLeakTests {
    @Test("FlowScope releases captured resources after cancellation")
    func scopeReleasesOnCancel() async {
        final class Holder: @unchecked Sendable {}
        weak var weakHolder: Holder?
        do {
            let holder = Holder()
            weakHolder = holder
            let scope = FlowScope()
            let task = scope.launch { [holder] in
                _ = holder
                while !Task.isCancelled {
                    await Task.yield()
                }
            }
            try? await Task.sleep(for: .seconds(0.01))
            scope.cancel()
            await task.value
        }
        try? await Task.sleep(for: .seconds(0.05))
        #expect(weakHolder == nil)
    }

    @Test("FlowScope deinit cancels in-flight tasks")
    func scopeDeinitCancels() async {
        let ranToCompletion = Mutex(false)
        do {
            let scope = FlowScope()
            _ = scope.launch {
                await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                } onCancel: {
                    // Task cancelled
                }
                ranToCompletion.withLock { $0 = true }
            }
            try? await Task.sleep(for: .seconds(0.01))
        }
        try? await Task.sleep(for: .seconds(0.05))
        #expect(ranToCompletion.withLock { $0 })
    }

    @Test("Completed tasks are removed from scope")
    func completedTasksRemoved() async {
        let scope = FlowScope()
        let task = scope.launch {
            // Completes immediately
        }
        await task.value
        try? await Task.sleep(for: .seconds(0.02))
        #expect(scope.activeTaskCount == 0)
    }

    @Test("Multiple scopes do not leak across each other")
    func isolatedScopes() async {
        weak var weakScope1: FlowScope?
        weak var weakScope2: FlowScope?
        do {
            let scope1 = FlowScope()
            let scope2 = FlowScope()
            weakScope1 = scope1
            weakScope2 = scope2
            scope1.cancel()
            scope2.cancel()
        }
        try? await Task.sleep(for: .seconds(0.05))
        #expect(weakScope1 == nil)
        #expect(weakScope2 == nil)
    }
}
