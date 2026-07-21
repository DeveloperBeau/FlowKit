#if canImport(Observation)
public import Observation
public import FlowCore
internal import FlowSharedModels

extension Flow where Element: Sendable {
    /// Creates a flow that emits an `@Observable` object's key-path value, then
    /// re-emits whenever it changes.
    ///
    /// Observation runs on the caller's actor (`#isolation`): construct this from
    /// the main actor and it observes on the main actor; construct it from a
    /// background actor that owns `root` and it observes there. Delivery is
    /// reliable only when `root` is mutated on that same actor, because
    /// `withObservationTracking` re-arms between changes and a mutation from a
    /// different actor can slip through that window. Keep mutation and
    /// observation on one actor and no change is missed.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    public init<Root: Observable & AnyObject & Sendable, KP: KeyPath<Root, Element> & Sendable>(
        observing root: Root,
        _ keyPath: KP,
        isolation: isolated (any Actor)? = #isolation
    ) where Element: Equatable {
        let boundActor: (any Actor)? = isolation
        self.init { collector in
            var previous: Element?
            for await value in _observationStream(of: root, keyPath: keyPath, isolation: boundActor) {
                if value != previous {
                    previous = value
                    await collector.emit(value)
                }
            }
        }
    }
}

/// An `AsyncStream` of a key-path's values driven by `withObservationTracking`,
/// with the observation loop pinned to `isolation` so it stays serialized with
/// mutations on that actor.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
private func _observationStream<Root: Observable & AnyObject & Sendable, Value: Sendable & Equatable, KP: KeyPath<Root, Value> & Sendable>(
    of root: Root,
    keyPath: KP,
    isolation: (any Actor)?
) -> AsyncStream<Value> {
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    let task = Task {
        await _runObservationLoop(root: root, keyPath: keyPath, continuation: continuation, isolation: isolation)
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
}

/// Yields the current value, then re-reads and yields on every change until
/// cancelled. Runs isolated to `isolation`; re-reading after each change means
/// the latest value is always delivered even across a burst.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
private func _runObservationLoop<Root: Observable & AnyObject & Sendable, Value: Sendable & Equatable, KP: KeyPath<Root, Value> & Sendable>(
    root: Root,
    keyPath: KP,
    continuation: AsyncStream<Value>.Continuation,
    isolation: isolated (any Actor)?
) async {
    var last = root[keyPath: keyPath]
    continuation.yield(last)
    while !Task.isCancelled {
        await _awaitChange(of: root, keyPath: keyPath, since: last, isolation: isolation)
        if Task.isCancelled { break }
        last = root[keyPath: keyPath]
        continuation.yield(last)
    }
    continuation.finish()
}

/// Suspends until `keyPath` differs from `previous`, or the task is cancelled.
/// After arming the observation it re-reads: a change that landed in the gap
/// between the last read and this registration already fired its `onChange`, so
/// arming alone would miss it — comparing to `previous` catches it and resumes
/// immediately. The continuation is resumed exactly once — by `onChange`, by the
/// gap re-read, or by cancellation — guarded by a lock so they can race safely.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
private func _awaitChange<Root: Observable & AnyObject & Sendable, Value: Equatable, KP: KeyPath<Root, Value> & Sendable>(
    of root: Root,
    keyPath: KP,
    since previous: Value,
    isolation: isolated (any Actor)?
) async {
    let box = Mutex<CheckedContinuation<Void, Never>?>(nil)
    @Sendable func resumeOnce() {
        let waiter = box.withLock { current -> CheckedContinuation<Void, Never>? in
            let waiter = current
            current = nil
            return waiter
        }
        waiter?.resume()
    }
    await withTaskCancellationHandler {
        await withCheckedContinuation(isolation: isolation) { continuation in
            box.withLock { $0 = continuation }
            if Task.isCancelled {
                resumeOnce()
                return
            }
            let current = withObservationTracking {
                root[keyPath: keyPath]
            } onChange: {
                resumeOnce()
            }
            if current != previous {
                resumeOnce()
            }
        }
    } onCancel: {
        resumeOnce()
    }
}
#endif
