import Testing
import FlowTesting

/// Runs `body` under a wall-clock safety net and fails by name when it hangs.
///
/// A correct recorder never reaches the bound. A broken one fails the test
/// with `what` in the message instead of parking the run.
func bounded<R: Sendable>(
    _ what: String,
    _ body: @escaping @Sendable () async throws -> R
) async throws -> R {
    do {
        return try await withThrowingTimeout(.seconds(30), clock: ContinuousClock(), body)
    } catch FlowTestError.timeout {
        Issue.record("Hung: \(what)")
        throw FlowTestError.timeout
    }
}
