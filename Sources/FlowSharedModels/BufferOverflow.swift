/// Defines what happens when a `SharedFlow` subscriber's buffer is full and a new
/// value arrives. Different overflow strategies suit different use cases:
///
/// - Use `.suspend` for analytics pipelines where every event matters and the
///   producer can tolerate backpressure (e.g., audit logs, billing events).
/// - Use `.dropOldest` for UI event streams where only recent events matter
///   (e.g., notification badges, scroll positions).
/// - Use `.dropLatest` for rate-limited upload queues where holding onto
///   existing work is more important than accepting new work.
public enum BufferOverflow: Sendable, Equatable {
    /// The emitter suspends until the subscriber consumes enough buffered values
    /// to make room. Preserves every value at the cost of backpressuring producers.
    case suspend

    /// The oldest buffered value is discarded to make room for the new value.
    /// Useful for "latest N events" semantics.
    case dropOldest

    /// The new value is discarded rather than buffered. Useful when in-flight work
    /// is more valuable than newer work.
    case dropLatest
}
