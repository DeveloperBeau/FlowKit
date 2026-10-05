import Foundation
public import FlowCore

/// Utility for testing multiple flows together. Each flow gets its own
/// `FlowTester` or `ThrowingFlowTester`, and all tester lifetimes are
/// bounded by the scope's closure.
public struct TestScope: Sendable {
    private let scope: FlowScope

    internal init(scope: FlowScope) {
        self.scope = scope
    }

    /// Runs `block` inside a new `TestScope`, collecting any flows registered
    /// via `scope.test(_:)`. All collection tasks are cancelled when the block
    /// exits.
    ///
    /// The timeout is real elapsed time (scaled by ``flowTestTimeoutScale``).
    @available(*, deprecated, message: "Read each flow with probing(_:) and suspend on its emissions. For a deadline, pass a TestClock through TestScope.run(timeout:clock:_:).")
    public static func run(
        timeout: Duration = .seconds(10),
        _ block: @escaping @Sendable (TestScope) async throws -> Void
    ) async throws {
        try await run(timeout: scaledTimeout(timeout), clock: ContinuousClock(), block)
    }

    /// Runs `block` inside a new `TestScope` with a timeout measured on
    /// `clock`, throwing `FlowTestError.timeout` once `clock` has advanced by
    /// `timeout`. Pass a `TestClock` to drive the deadline by hand. The
    /// timeout is used as given, without ``flowTestTimeoutScale``.
    public static func run<C: Clock>(
        timeout: Duration = .seconds(10),
        clock: C,
        _ block: @escaping @Sendable (TestScope) async throws -> Void
    ) async throws where C.Duration == Duration {
        let flowScope = FlowScope()
        defer { flowScope.cancel() }

        let testScope = TestScope(scope: flowScope)

        try await withThrowingTimeout(timeout, clock: clock) {
            try await block(testScope)
        }
    }

    /// Registers a non-throwing flow in this scope and returns a `FlowTester`.
    public func test<Element: Sendable>(
        _ flow: Flow<Element>
    ) async throws -> FlowTester<Element> {
        let tester = FlowTester<Element>()
        scope.launch {
            await flow.collect { value in
                await tester.recordValue(value)
            }
            await tester.recordCompletion()
        }
        return tester
    }

    /// Registers a throwing flow in this scope and returns a `ThrowingFlowTester`.
    public func test<Element: Sendable>(
        _ flow: ThrowingFlow<Element>
    ) async throws -> ThrowingFlowTester<Element> {
        let tester = ThrowingFlowTester<Element>()
        scope.launch {
            do {
                try await flow.collect { value in
                    await tester.recordValue(value)
                }
                await tester.recordCompletion()
            } catch {
                await tester.recordError(error)
            }
        }
        return tester
    }
}
