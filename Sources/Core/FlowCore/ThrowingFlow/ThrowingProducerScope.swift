public import FlowSharedModels

/// The producer handle a ``ThrowingFlow/channelFlow(bufferCapacity:onBufferOverflow:_:)``
/// or ``ThrowingFlow/callbackFlow(bufferCapacity:onBufferOverflow:_:)`` block receives.
///
/// It is a ``ProducerScope`` that can also end the flow with an error, for
/// callback and delegate APIs whose last callback reports a failure. The first
/// close wins: a later ``close()`` or ``close(throwing:)`` is ignored.
public struct ThrowingProducerScope<Element: Sendable>: Sendable {
    internal let base: ProducerScope<Element>
    /// The error the flow fails with once the buffered values have drained.
    internal let failure: Mutex<(any Error)?>

    internal init(base: ProducerScope<Element>, failure: Mutex<(any Error)?>) {
        self.base = base
        self.failure = failure
    }

    /// Pushes `value` downstream without suspending, the same as ``ProducerScope/trySend(_:)``.
    @discardableResult
    public func trySend(_ value: Element) -> ChannelSendResult {
        base.trySend(value)
    }

    /// Pushes `value` downstream, suspending for backpressure under the
    /// `.suspend` overflow policy, the same as ``ProducerScope/send(_:)``.
    @discardableResult
    public func send(_ value: Element) async -> ChannelSendResult {
        await base.send(value)
    }

    /// Ends the flow without an error once the already-buffered values drain.
    public func close() {
        base.close()
    }

    /// Ends the flow with `error`. The collector receives every value sent
    /// before this call, then its `collect` throws `error`.
    ///
    /// The call is ignored when the flow has already ended, whether by an
    /// earlier close or because the collector was cancelled.
    public func close(throwing error: any Error) {
        // Decided under the close lock, so a close that already won cannot be
        // turned into a failure by a racing caller.
        base.closeState.withLock { state in
            guard !state.isClosed else { return }
            failure.withLock { stored in
                if stored == nil { stored = error }
            }
        }
        base.close()
    }

    /// Suspends the producer block until the flow closes, then runs `onClose`
    /// exactly once, the same as ``ProducerScope/awaitClose(_:)``.
    public func awaitClose(_ onClose: @escaping @Sendable () -> Void = {}) async {
        await base.awaitClose(onClose)
    }
}
