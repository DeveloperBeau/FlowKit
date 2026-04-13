import Foundation

/// A `Clock` whose time is advanced manually by tests. Used to make
/// time-dependent operators (`debounce`, `throttle`, `sample`, retry
/// with backoff, `SharingStrategy.whileSubscribed`) deterministic in
/// tests — no real-time sleeps, no CI flakiness.
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
        let toWake: [Sleeper] = lock.withLock {
            state.currentInstant = state.currentInstant.advanced(by: duration)
            let newNow = state.currentInstant

            var toWake: [Sleeper] = []
            while let first = state.sleepers.first, first.deadline <= newNow {
                toWake.append(state.sleepers.removeFirst())
            }
            return toWake
        }

        for sleeper in toWake {
            sleeper.continuation.resume()
        }

        await Task.yield()
    }

    /// Advances virtual time through all currently-registered sleepers,
    /// waking them in deadline order.
    public func run() async {
        while true {
            let nextDeadline: Instant? = lock.withLock {
                state.sleepers.first?.deadline
            }

            guard let deadline = nextDeadline else { return }
            let delta = now.duration(to: deadline)
            if delta > .zero {
                await advance(by: delta)
            } else {
                await Task.yield()
            }
        }
    }
}
