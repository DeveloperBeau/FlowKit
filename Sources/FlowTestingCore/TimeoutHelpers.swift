import Foundation
import FlowSharedModels

/// Runs `body` with a real-time wall-clock timeout. Throws
/// `FlowTestError.timeout` if `body` does not complete within `duration`.
public func withThrowingTimeout<R: Sendable>(
    _ duration: Duration,
    _ body: @escaping @Sendable () async throws -> R
) async throws -> R {
    try await withThrowingTaskGroup(of: R?.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            try await Task.sleep(for: duration)
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
