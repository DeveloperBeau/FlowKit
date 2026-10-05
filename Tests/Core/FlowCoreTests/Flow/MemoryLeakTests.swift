import Testing
import FlowTestSupport
import Foundation
import FlowSharedModels
import FlowTestingCore
@testable import FlowCore

@Suite("Memory safety")
struct MemoryLeakTests {
    @Test("FlowScope releases captured resources after cancellation")
    func scopeReleasesOnCancel() async {
        final class Holder: @unchecked Sendable {
            let released: Signal
            init(released: Signal) { self.released = released }
            deinit { released.fire() }
        }
        let released = Signal()
        let started = Signal()
        weak var weakHolder: Holder?
        do {
            let holder = Holder(released: released)
            weakHolder = holder
            let scope = FlowScope()
            let task = scope.launch { [holder] in
                _ = holder
                started.fire()
                await parkUntilCancelled()
            }
            await started.wait()
            scope.cancel()
            await task.value
        }
        // The task's captured holder is freed when its closure is released.
        await released.wait()
        #expect(weakHolder == nil)
    }

    @Test("FlowScope deinit cancels in-flight tasks")
    func scopeDeinitCancels() async {
        let ranToCompletion = Signal()
        let started = Signal()
        do {
            let scope = FlowScope()
            _ = scope.launch {
                started.fire()
                await parkUntilCancelled()
                ranToCompletion.fire()
            }
            // Ensure the task is running before the scope deinits.
            await started.wait()
        }
        // The scope is gone; its deinit must have cancelled the parked body.
        await ranToCompletion.wait()
        #expect(ranToCompletion.hasFired)
    }

    @Test("Completed tasks are removed from scope")
    func completedTasksRemoved() async {
        let scope = FlowScope()
        let task = scope.launch {
            // Completes immediately
        }
        // The task removes itself from the scope as the last step of its
        // closure, so completion implies removal — no sleep needed.
        await task.value
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
        #expect(weakScope1 == nil)
        #expect(weakScope2 == nil)
    }
}
