public import FlowSharedModels

/// The outcome of a non-suspending ``ProducerScope/trySend(_:)``.
public enum ChannelSendResult: Sendable, Equatable {
    /// The value was accepted into the buffer (possibly evicting an older
    /// value under a `.dropOldest` policy).
    case enqueued

    /// The buffer was full and the value was discarded per the overflow
    /// policy (`.dropLatest`).
    case dropped

    /// The channel is already closed; the value was not delivered.
    case closed
}

/// The producer handle a ``Flow/channelFlow(bufferCapacity:onBufferOverflow:_:)``
/// or ``Flow/callbackFlow(bufferCapacity:onBufferOverflow:_:)`` block receives.
///
/// It bridges a callback or delegate API into a `Flow`: push values with the
/// non-suspending ``trySend(_:)`` from inside a callback, then park the block
/// on ``awaitClose(_:)`` so the bridge stays registered until the flow is torn
/// down.
public struct ProducerScope<Element: Sendable>: Sendable {
    @usableFromInline
    internal struct CloseState {
        var isClosed = false
        var awaitCloseInvoked = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    @usableFromInline
    internal let continuation: AsyncStream<Element>.Continuation
    @usableFromInline
    internal let closeState: Mutex<CloseState>

    @usableFromInline
    internal init(continuation: AsyncStream<Element>.Continuation, closeState: Mutex<CloseState>) {
        self.continuation = continuation
        self.closeState = closeState
    }

    /// Pushes `value` downstream without suspending. Safe to call from a
    /// synchronous callback on any thread.
    ///
    /// - Returns: ``ChannelSendResult/enqueued`` when buffered,
    ///   ``ChannelSendResult/dropped`` when the buffer was full under a
    ///   dropping policy, or ``ChannelSendResult/closed`` once the flow has
    ///   ended.
    @discardableResult
    public func trySend(_ value: Element) -> ChannelSendResult {
        switch continuation.yield(value) {
        case .enqueued:
            return .enqueued
        case .dropped:
            return .dropped
        case .terminated:
            return .closed
        @unknown default:
            return .dropped
        }
    }

    /// Whether the channel has closed. Once `true`, ``trySend(_:)`` returns
    /// ``ChannelSendResult/closed``.
    public var isClosedForSend: Bool {
        closeState.withLock { $0.isClosed }
    }

    /// Ends the flow from the producer side. The collector's `collect` returns
    /// once the already-buffered values drain.
    public func close() {
        continuation.finish()
    }

    /// Suspends the producer block until the flow closes — because the
    /// collector cancelled, the collection finished, or ``close()`` was
    /// called — then runs `onClose` for teardown (unregister the callback,
    /// stop the delegate). Runs `onClose` exactly once.
    ///
    /// A `callbackFlow` block that registers a callback must end on
    /// `awaitClose`; otherwise the block returns immediately, the flow
    /// completes, and the callback fires into a dead channel. In debug builds
    /// `callbackFlow` asserts that this was called.
    public func awaitClose(_ onClose: @escaping @Sendable () -> Void = {}) async {
        closeState.withLock { $0.awaitCloseInvoked = true }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyClosed = closeState.withLock { state -> Bool in
                    if state.isClosed { return true }
                    state.waiter = continuation
                    return false
                }
                if alreadyClosed { continuation.resume() }
            }
        } onCancel: {
            markClosed()
        }
        onClose()
    }

    /// Marks the channel closed and wakes a parked ``awaitClose(_:)``. Called
    /// from the stream's termination, the collector loop, and cancellation —
    /// idempotent, so the parked block resumes exactly once no matter how many
    /// of those fire.
    @usableFromInline
    internal func markClosed() {
        let waiter = closeState.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }
}

extension Flow {
    /// Builds a cold flow from a producer block that pushes values through a
    /// channel. Each collector runs the block independently.
    ///
    /// The block receives a ``ProducerScope`` to ``ProducerScope/trySend(_:)``
    /// values into and ``ProducerScope/awaitClose(_:)`` on for teardown. The
    /// flow ends when the block calls ``ProducerScope/close()``, returns, or
    /// the collector is cancelled.
    ///
    /// - Parameters:
    ///   - bufferCapacity: How many unconsumed values the channel holds.
    ///     Zero or negative means unbounded.
    ///   - onBufferOverflow: What a full buffer does with a new value.
    ///     `.dropOldest` (the default) evicts the oldest, keeping the newest —
    ///     the right choice for conflatable signals like location updates.
    ///     `.dropLatest` discards the incoming value. `.suspend` is not
    ///     honoured here because ``ProducerScope/trySend(_:)`` never suspends;
    ///     it degrades to unbounded buffering. For true producer backpressure,
    ///     apply `.buffer(size:policy:.suspend)` downstream.
    public static func channelFlow(
        bufferCapacity: Int = 64,
        onBufferOverflow: BufferOverflow = .dropOldest,
        _ block: @escaping @Sendable (ProducerScope<Element>) async -> Void
    ) -> Flow<Element> {
        Flow { downstream in
            let (stream, continuation) = AsyncStream<Element>.makeStream(
                bufferingPolicy: channelBufferingPolicy(capacity: bufferCapacity, overflow: onBufferOverflow)
            )
            let scope = ProducerScope<Element>(continuation: continuation, closeState: Mutex(.init()))
            continuation.onTermination = { _ in scope.markClosed() }

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await block(scope)
                    // The block returned on its own (it did not park on
                    // awaitClose): complete the flow.
                    continuation.finish()
                }
                group.addTask {
                    for await value in stream {
                        await downstream.emit(value)
                        if Task.isCancelled { break }
                    }
                    // Downstream drained or cancelled: wake a parked producer
                    // so its teardown runs, and make sure the stream is closed.
                    scope.markClosed()
                    continuation.finish()
                }
                await group.waitForAll()
            }
        }
    }

    /// A ``channelFlow(bufferCapacity:onBufferOverflow:_:)`` for bridging a
    /// callback or delegate API. Register the callback, ``ProducerScope/trySend(_:)``
    /// from it, and end the block on ``ProducerScope/awaitClose(_:)`` to
    /// unregister when the flow tears down.
    ///
    /// In debug builds this asserts the block parked on `awaitClose` (or
    /// closed), catching the bug where a callback is registered but the block
    /// returns immediately, leaving the callback firing into a dead channel.
    public static func callbackFlow(
        bufferCapacity: Int = 64,
        onBufferOverflow: BufferOverflow = .dropOldest,
        _ block: @escaping @Sendable (ProducerScope<Element>) async -> Void
    ) -> Flow<Element> {
        channelFlow(bufferCapacity: bufferCapacity, onBufferOverflow: onBufferOverflow) { scope in
            await block(scope)
            assert(
                scope.closeState.withLock { $0.awaitCloseInvoked || $0.isClosed },
                "callbackFlow block returned without calling awaitClose or close; a callback bridge must keep the flow alive until it is torn down"
            )
        }
    }
}

/// Maps a capacity and overflow policy to an `AsyncStream` buffering policy.
/// `.suspend` degrades to unbounded because a non-suspending `trySend` cannot
/// apply producer backpressure (see `channelFlow`'s docs).
private func channelBufferingPolicy<Element>(
    capacity: Int,
    overflow: BufferOverflow
) -> AsyncStream<Element>.Continuation.BufferingPolicy {
    guard capacity > 0 else { return .unbounded }
    switch overflow {
    case .dropOldest:
        return .bufferingNewest(capacity)
    case .dropLatest:
        return .bufferingOldest(capacity)
    case .suspend:
        return .unbounded
    }
}
