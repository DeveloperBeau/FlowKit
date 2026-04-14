import Foundation

/// Controls when a cold `Flow` converted to a hot stream (via `asStateFlow` or
/// `asSharedFlow`) starts and stops its upstream collection. Equivalent to
/// Kotlin Flow's `SharingStarted` but named for Swift API Design Guidelines.
///
/// ## Choosing a strategy
///
/// - **`.eager`**: the upstream starts immediately when the hot flow is created,
///   regardless of subscribers. Use when you want to pre-warm the stream (e.g.,
///   the current user's profile that every screen will eventually read).
///
/// - **`.lazy`**: the upstream starts when the first subscriber arrives and
///   stays active until the owning scope ends. Use when the stream has no-op
///   value without subscribers, but once started should remain available.
///
/// - **`.whileSubscribed(stopTimeout:replayExpiration:)`**: the upstream starts
///   on first subscriber and stops `stopTimeout` after the last subscriber leaves.
///   The recommended default for UI state on Android-equivalent lifecycles,
///   typically with `stopTimeout: .seconds(5)` to handle configuration changes
///   and brief tab switches without tearing down and re-establishing state.
public enum SharingStrategy: Sendable, Equatable {
    /// Starts the upstream immediately and keeps it running until the owning
    /// scope ends, regardless of subscriber count.
    case eager

    /// Starts the upstream on the first subscriber and keeps it running until
    /// the owning scope ends, even after all subscribers leave.
    case lazy

    /// Starts the upstream on the first subscriber. When the last subscriber
    /// leaves, waits `stopTimeout` before stopping the upstream (giving a new
    /// subscriber a chance to arrive and keep the stream alive). The replay
    /// cache is cleared `replayExpiration` after the last subscriber leaves.
    ///
    /// Recommended default for UI state: `.whileSubscribed(stopTimeout: .seconds(5))`.
    case whileSubscribed(stopTimeout: Duration = .zero, replayExpiration: Duration = .zero)
}
