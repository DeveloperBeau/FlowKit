internal import Foundation
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
    /// Backpressure gate for the `.suspend` overflow policy; `nil` under the
    /// dropping policies and for unbounded channels, where ``send(_:)`` never
    /// suspends.
    internal let gate: SendGate?

    internal init(
        continuation: AsyncStream<Element>.Continuation,
        closeState: Mutex<CloseState>,
        gate: SendGate? = nil
    ) {
        self.continuation = continuation
        self.closeState = closeState
        self.gate = gate
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

    /// Pushes `value` downstream, suspending for backpressure under the
    /// `.suspend` overflow policy.
    ///
    /// With `onBufferOverflow: .suspend` and a positive `bufferCapacity`, this
    /// suspends while the channel already holds `bufferCapacity` unconsumed
    /// values and resumes once the collector has processed one — a slow
    /// downstream pauses the producer instead of losing values. Under the
    /// dropping policies or an unbounded channel it behaves exactly like
    /// ``trySend(_:)`` and never suspends.
    ///
    /// Only suspending sends participate in backpressure; a ``trySend(_:)``
    /// on the same channel enqueues without occupying a slot.
    ///
    /// - Parameter value: The value to deliver downstream.
    /// - Returns: ``ChannelSendResult/enqueued`` when buffered;
    ///   ``ChannelSendResult/dropped`` when a dropping policy discarded it;
    ///   ``ChannelSendResult/closed`` when the channel was already closed —
    ///   including a ``close()`` racing the send, and cancellation of the
    ///   producer before or while the send was suspended. A `.closed` send
    ///   never delivers its value.
    @discardableResult
    public func send(_ value: Element) async -> ChannelSendResult {
        guard !isClosedForSend else { return .closed }
        if let gate {
            let id = UUID()
            let acquired = await withTaskCancellationHandler {
                await gate.acquire(id: id)
            } onCancel: {
                Task { await gate.cancel(id: id) }
            }
            guard acquired else { return .closed }
            let result = trySend(value)
            if result != .enqueued {
                // The value never reached the buffer, so the consumer will
                // never release the slot this send acquired.
                await gate.release()
            }
            return result
        }
        return trySend(value)
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
        let (waiter, firstClose) = closeState.withLock { state -> (CheckedContinuation<Void, Never>?, Bool) in
            guard !state.isClosed else { return (nil, false) }
            state.isClosed = true
            defer { state.waiter = nil }
            return (state.waiter, true)
        }
        waiter?.resume()
        if firstClose, let gate {
            // Wake any producer suspended in `send` so teardown can finish.
            Task { await gate.close() }
        }
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
    ///     `.dropLatest` discards the incoming value. `.suspend` gives true
    ///     producer backpressure through ``ProducerScope/send(_:)``, which
    ///     suspends while `bufferCapacity` values are unconsumed; the
    ///     non-suspending ``ProducerScope/trySend(_:)`` cannot backpressure
    ///     and buffers without bound under this policy.
    public static func channelFlow(
        bufferCapacity: Int = 64,
        onBufferOverflow: BufferOverflow = .dropOldest,
        _ block: @escaping @Sendable (ProducerScope<Element>) async -> Void
    ) -> Flow<Element> {
        Flow { downstream in
            let (stream, continuation) = AsyncStream<Element>.makeStream(
                bufferingPolicy: channelBufferingPolicy(capacity: bufferCapacity, overflow: onBufferOverflow)
            )
            // The stream stores values under `.suspend`; the gate is what
            // bounds them, by suspending `send` past `bufferCapacity`.
            let gate: SendGate? = (onBufferOverflow == .suspend && bufferCapacity > 0)
                ? SendGate(capacity: bufferCapacity)
                : nil
            let scope = ProducerScope<Element>(
                continuation: continuation,
                closeState: Mutex(.init()),
                gate: gate
            )
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
                        // The consumer has processed the value: free its
                        // backpressure slot so a suspended send can resume.
                        await gate?.release()
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
/// `.suspend` maps to unbounded storage: the `SendGate` is what enforces the
/// capacity, by suspending `send` — a bounded stream policy here would
/// silently drop values instead of backpressuring.
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
