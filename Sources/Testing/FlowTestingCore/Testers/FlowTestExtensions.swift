import Foundation
public import FlowCore

extension Flow {
    /// Collects this flow and provides a `FlowTester` for structured assertions.
    /// The closure has `timeout` wall-clock time to complete all expectations.
    /// After the closure exits, the tester's collection task is cancelled.
    @available(*, deprecated, message: "Read the flow with probing(_:) and suspend on its emissions. For a deadline, pass a TestClock through test(timeout:clock:_:).")
    public func test(
        timeout: Duration = .seconds(10),
        _ block: @escaping @Sendable (FlowTester<Element>) async throws -> Void
    ) async throws {
        try await test(timeout: scaledTimeout(timeout), clock: ContinuousClock(), block)
    }

    /// Collects this flow and provides a `FlowTester`, with a timeout measured
    /// on `clock`: the closure throws `FlowTestError.timeout` once `clock` has
    /// advanced by `timeout`. Pass a `TestClock` to drive the deadline by
    /// hand. The timeout is used as given, without ``flowTestTimeoutScale``.
    public func test<C: Clock>(
        timeout: Duration = .seconds(10),
        clock: C,
        _ block: @escaping @Sendable (FlowTester<Element>) async throws -> Void
    ) async throws where C.Duration == Duration {
        let tester = FlowTester<Element>()

        let collectionTask = Task {
            await self.collect { value in
                await tester.recordValue(value)
            }
            await tester.recordCompletion()
        }

        defer { collectionTask.cancel() }

        try await withThrowingTimeout(timeout, clock: clock) {
            try await block(tester)
        }
    }
}

extension ThrowingFlow {
    /// Collects this throwing flow and provides a `ThrowingFlowTester` for
    /// structured assertions including error matchers.
    @available(*, deprecated, message: "Read the flow with probing(_:) and suspend on its emissions. For a deadline, pass a TestClock through test(timeout:clock:_:).")
    public func test(
        timeout: Duration = .seconds(10),
        _ block: @escaping @Sendable (ThrowingFlowTester<Element>) async throws -> Void
    ) async throws {
        try await test(timeout: scaledTimeout(timeout), clock: ContinuousClock(), block)
    }

    /// Collects this throwing flow and provides a `ThrowingFlowTester`, with a
    /// timeout measured on `clock`: the closure throws `FlowTestError.timeout`
    /// once `clock` has advanced by `timeout`. Pass a `TestClock` to drive the
    /// deadline by hand. The timeout is used as given, without
    /// ``flowTestTimeoutScale``.
    public func test<C: Clock>(
        timeout: Duration = .seconds(10),
        clock: C,
        _ block: @escaping @Sendable (ThrowingFlowTester<Element>) async throws -> Void
    ) async throws where C.Duration == Duration {
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

        try await withThrowingTimeout(timeout, clock: clock) {
            try await block(tester)
        }
    }
}
