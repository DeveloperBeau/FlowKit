import Foundation
import FlowSharedModels

/// Multiplier applied to every FlowTesting wall-clock timeout, read once from
/// the `FLOWKIT_TIMEOUT_SCALE` environment variable (default 1, values below
/// 1 are clamped to 1).
///
/// Wall-clock timeouts are hang detectors, not performance assertions. On a
/// constrained CI runner (2-3 cores driving a simulator with every suite in
/// parallel), the executor backlog can stretch a locally-instant test past a
/// fixed timeout and fail runs that would pass given breathing room. Set the
/// variable on such runners (e.g. `TEST_RUNNER_FLOWKIT_TIMEOUT_SCALE=6` for
/// xcodebuild, which forwards `TEST_RUNNER_`-prefixed variables to the test
/// process) to widen every timeout without touching individual tests. Fast
/// tests are unaffected: successes never wait out a timeout.
public let flowTestTimeoutScale: Double = ProcessInfo.processInfo
    .environment["FLOWKIT_TIMEOUT_SCALE"]
    .flatMap(Double.init)
    .map { max($0, 1) } ?? 1

/// Applies ``flowTestTimeoutScale`` to a timeout duration.
internal func scaledTimeout(_ duration: Duration) -> Duration {
    guard flowTestTimeoutScale != 1 else { return duration }
    let (seconds, attoseconds) = duration.components
    let nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) * 1e-9
    return .nanoseconds(Int64(nanoseconds * flowTestTimeoutScale))
}

/// Runs `body` with a real-time wall-clock timeout. Throws
/// `FlowTestError.timeout` if `body` does not complete within `duration`
/// (scaled by ``flowTestTimeoutScale``).
public func withThrowingTimeout<R: Sendable>(
    _ duration: Duration,
    _ body: @escaping @Sendable () async throws -> R
) async throws -> R {
    try await withThrowingTaskGroup(of: R?.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            try await Task.sleep(for: scaledTimeout(duration))
            return nil
        }

        let first = try await group.next()
        group.cancelAll()

        switch first {
        case .some(.some(let value)):
            return value
        case .some(.none), .none:
            throw FlowTestError.timeout
        }
    }
}
