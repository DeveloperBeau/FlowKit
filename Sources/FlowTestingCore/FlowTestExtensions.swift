import Foundation
public import FlowCore

extension Flow {
    /// Collects this flow and provides a `FlowTester` for structured assertions.
    /// The closure has `timeout` wall-clock time to complete all expectations.
    /// After the closure exits, the tester's collection task is cancelled.
    public func test(
        timeout: Duration = .seconds(2),
        _ block: @escaping @Sendable (FlowTester<Element>) async throws -> Void
    ) async throws {
        let tester = FlowTester<Element>()

        let collectionTask = Task {
            await self.collect { value in
                await tester.recordValue(value)
            }
            await tester.recordCompletion()
        }

        defer { collectionTask.cancel() }

        try await withThrowingTimeout(timeout) {
            try await block(tester)
        }
    }
}

extension ThrowingFlow {
    /// Collects this throwing flow and provides a `ThrowingFlowTester` for
    /// structured assertions including error matchers.
    public func test(
        timeout: Duration = .seconds(2),
        _ block: @escaping @Sendable (ThrowingFlowTester<Element>) async throws -> Void
    ) async throws {
        let tester = ThrowingFlowTester<Element>()

        let collectionTask = Task {
            do {
                try await self.collect { value in
                    await tester.recordValue(value)
                }
                await tester.recordCompletion()
            } catch {
                await tester.recordError(error)
            }
        }

        defer { collectionTask.cancel() }

        try await withThrowingTimeout(timeout) {
            try await block(tester)
        }
    }
}
