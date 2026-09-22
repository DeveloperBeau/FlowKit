/// Errors thrown by `FlowTester` / `ThrowingFlowTester` when assertions can't
/// be satisfied. These are typically caught by Swift Testing's `Issue.record`
/// machinery and turned into test failures with source-location attribution.
///
/// This type lives in `FlowSharedModels` (rather than `FlowTestingCore`) so
/// that consumer code writing custom matchers can reference it without pulling
/// in the full testing infrastructure, and so that `FlowTestClock` tests can
/// share the error vocabulary without a circular dependency.
public enum FlowTestError: Error, Sendable, Equatable {
    /// The assertion's timeout expired before the expected event occurred.
    case timeout

    /// The assertion expected a value but the flow completed instead.
    case unexpectedCompletion

    /// The assertion expected completion or a specific event but received a
    /// value that did not match.
    case unexpectedValue
}
