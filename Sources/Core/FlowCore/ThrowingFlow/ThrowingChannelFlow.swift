public import FlowSharedModels

extension ThrowingFlow {
    /// Builds a cold throwing flow from a producer block that pushes values
    /// through a channel. Each collector runs the block independently.
    ///
    /// This is ``Flow/channelFlow(bufferCapacity:onBufferOverflow:_:)`` for a
    /// source that can fail. The flow fails when the block calls
    /// ``ThrowingProducerScope/close(throwing:)`` or throws. The collector
    /// receives every value buffered before the failure, then `collect` throws
    /// the error. The flow ends without an error when the block calls
    /// ``ThrowingProducerScope/close()``, returns, or the collector is
    /// cancelled. An error the block raises after the flow has ended, or
    /// because the collector was cancelled, is dropped.
    ///
    /// - Parameters:
    ///   - bufferCapacity: How many unconsumed values the channel holds.
    ///     Zero or negative means unbounded.
    ///   - onBufferOverflow: What a full buffer does with a new value, with
    ///     the same meaning as on ``Flow/channelFlow(bufferCapacity:onBufferOverflow:_:)``.
    public static func channelFlow(
        bufferCapacity: Int = 64,
        onBufferOverflow: BufferOverflow = .dropOldest,
        _ block: @escaping @Sendable (ThrowingProducerScope<Element>) async throws -> Void
    ) -> ThrowingFlow<Element> {
        ThrowingFlow { downstream in
            let (stream, continuation) = AsyncStream<Element>.makeStream(
                bufferingPolicy: channelBufferingPolicy(capacity: bufferCapacity, overflow: onBufferOverflow)
            )
            let gate: SendGate? = (onBufferOverflow == .suspend && bufferCapacity > 0)
                ? SendGate(capacity: bufferCapacity)
                : nil
            let base = ProducerScope<Element>(
                continuation: continuation,
                closeState: Mutex(.init()),
                gate: gate
            )
            let failure = Mutex<(any Error)?>(nil)
            let scope = ThrowingProducerScope<Element>(base: base, failure: failure)
            continuation.onTermination = { _ in base.markClosed() }

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        try await block(scope)
                        continuation.finish()
                    } catch {
                        // A block that throws because its collector went away
                        // is tearing down, not failing.
                        if Task.isCancelled {
                            scope.close()
                        } else {
                            scope.close(throwing: error)
                        }
                    }
                }
                group.addTask {
                    // Runs on every exit, a downstream error included: wake a
                    // parked producer so its teardown runs.
                    defer {
                        base.markClosed()
                        continuation.finish()
                    }
                    for await value in stream {
                        try await downstream.emit(value)
                        await gate?.release()
                        if Task.isCancelled { break }
                    }
                }
                try await group.waitForAll()
            }
            if let error = failure.withLock({ $0 }) { throw error }
        }
    }

    /// A ``channelFlow(bufferCapacity:onBufferOverflow:_:)`` for bridging a
    /// callback or delegate API that can end with an error.
    ///
    /// Register the callback, ``ThrowingProducerScope/trySend(_:)`` from it,
    /// report a failure with ``ThrowingProducerScope/close(throwing:)``, and
    /// end the block on ``ThrowingProducerScope/awaitClose(_:)`` to unregister
    /// when the flow tears down. In debug builds this asserts that a block
    /// which returns has parked on `awaitClose` or closed.
    public static func callbackFlow(
        bufferCapacity: Int = 64,
        onBufferOverflow: BufferOverflow = .dropOldest,
        _ block: @escaping @Sendable (ThrowingProducerScope<Element>) async throws -> Void
    ) -> ThrowingFlow<Element> {
        channelFlow(bufferCapacity: bufferCapacity, onBufferOverflow: onBufferOverflow) { scope in
            try await block(scope)
            assert(
                scope.base.closeState.withLock { $0.awaitCloseInvoked || $0.isClosed },
                "callbackFlow block returned without calling awaitClose or close; a callback bridge must keep the flow alive until it is torn down"
            )
        }
    }
}
