import Foundation

/// A `Clock` whose time is advanced manually by tests. Used to make
/// time-dependent operators (`debounce`, `throttle`, `sample`, retry
/// with backoff, `SharingStrategy.whileSubscribed`) deterministic in
/// tests with no real-time sleeps and no CI flakiness.
///
/// ## Usage
///
/// ```swift
/// @Test("debounce collapses rapid inputs")
/// func debounceCollapsesRapidInputs() async throws {
///     let clock = TestClock()
///     let queries = MutableSharedFlow<String>()
///
///     try await queries.asFlow()
///         .debounce(for: .milliseconds(300), clock: clock)
///         .test { tester in
///             await queries.emit("h")
///             await clock.advance(by: .milliseconds(100))
///             await queries.emit("he")
///             await clock.advance(by: .milliseconds(100))
///             await queries.emit("hel")
///             await tester.expectNoValue(within: .milliseconds(100))
///             await clock.advance(by: .milliseconds(400))
///             try await tester.expectValue("hel")
///         }
/// }
/// ```
public final class TestClock: Clock, @unchecked Sendable {
    public struct Instant: InstantProtocol {
        public typealias Duration = Swift.Duration
        public let offset: Duration

        public init(offset: Duration = .zero) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    public typealias Duration = Swift.Duration

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var currentInstant: Instant = Instant()
        var sleepers: [Sleeper] = []
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    public var now: Instant {
        lock.withLock { state.currentInstant }
    }

    public var minimumResolution: Duration { .zero }

    /// The number of sleepers currently waiting on this clock. A test uses it
    /// to wait until a time-based operator has registered its sleep before
    /// advancing, instead of racing that registration with a real sleep.
    public var sleeperCount: Int {
        lock.withLock { state.sleepers.count }
    }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        // Each sleeper gets a unique ID so the cancellation handler can
        // remove exactly the right entry from the sleepers array.
        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock { [self] in
                    // Fast path: deadline already passed.
                    if state.currentInstant >= deadline {
                        continuation.resume()
                        return
                    }

                    // Check cancellation before registering.
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let sleeper = Sleeper(id: id, deadline: deadline, continuation: continuation)
                    state.sleepers.append(sleeper)
                    state.sleepers.sort { $0.deadline < $1.deadline }
                }
            }
        } onCancel: {
            // Remove this sleeper and resume its continuation so it's
            // never orphaned. Safe to call from any context.
            let continuation: CheckedContinuation<Void, any Error>? = lock.withLock { [self] in
                if let idx = state.sleepers.firstIndex(where: { $0.id == id }) {
                    let sleeper = state.sleepers.remove(at: idx)
                    return sleeper.continuation
                }
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Advances virtual time by `duration` and wakes any sleepers whose
    /// deadlines have now passed. Sleepers wake in deadline order.
    public func advance(by duration: Duration) async {
        await advance(to: lock.withLock { state.currentInstant.advanced(by: duration) })
    }

    /// Advances virtual time to `deadline`, waking sleepers in deadline order.
    ///
    /// Sleepers are resumed one at a time with a scheduler drain between
    /// each, so a woken task normally runs its follow-on work before the
    /// next sleeper is resumed. Merely resuming the whole batch in order
    /// would not even approximate that: resuming only schedules a task, and
    /// the executor is free to run a later-deadline task first. One-at-a-time
    /// waking with drains is the strategy pointfreeco/swift-clocks proved out.
    ///
    /// Only the *resumption* order is guaranteed. The drain is a best-effort
    /// fence: under a saturated cooperative pool a woken task's follow-on
    /// work can still interleave with a later sleeper's. Code that must
    /// observe effects in deadline order should advance incrementally and
    /// await the woken work between steps.
    public func advance(to deadline: Instant) async {
        while true {
            // Drain first so work triggered by the previous wake (including
            // re-registered sleeps from repeating operators) settles before
            // the next sleeper is chosen.
            await Self.drainScheduler()

            let next: Sleeper? = lock.withLock {
                guard let first = state.sleepers.first, first.deadline <= deadline else {
                    if state.currentInstant < deadline {
                        state.currentInstant = deadline
                    }
                    return nil
                }
                state.currentInstant = first.deadline
                return state.sleepers.removeFirst()
            }

            guard let sleeper = next else {
                await Self.drainScheduler()
                return
            }
            sleeper.continuation.resume()
        }
    }

    /// Advances virtual time through all registered sleepers, waking them in
    /// deadline order, until none remain (including sleeps re-registered by
    /// woken tasks along the way).
    public func run() async {
        await Self.drainScheduler()
        while let deadline = lock.withLock({ state.sleepers.first?.deadline }) {
            await advance(to: deadline)
        }
    }

    /// Suspends until the cooperative pool has run the tasks made ready by a
    /// wake. Awaiting a detached task forces the executor to get through the
    /// work already queued ahead of it first; one plain `Task.yield()` only
    /// requeues the caller once and gives no such guarantee under load.
    ///
    /// The drain runs at default priority deliberately. A background-priority
    /// drain would also flush below-default work, but iOS simulators throttle
    /// background QoS so hard that each hop costs seconds and clock-driven
    /// tests blow their timeouts; everything a test clock wakes runs at
    /// default or above, so default-priority drains give the same ordering
    /// guarantee without the throttling.
    private static func drainScheduler() async {
        for _ in 0..<20 {
            await Task.detached { await Task.yield() }.value
        }
    }
}
