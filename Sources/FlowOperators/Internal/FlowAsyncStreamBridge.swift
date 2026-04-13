public import FlowCore

extension Flow {
    /// Bridges this cold flow into an `AsyncStream`. Used internally by
    /// combining operators (`zip`, `combineLatest`, `merge`) that delegate
    /// to `swift-async-algorithms` which operates on `AsyncSequence`.
    ///
    /// The flow is collected in a child task; the stream finishes when the
    /// flow completes or the consuming task is cancelled.
    ///
    /// - Important: The returned stream must be iterated within a structured context.
    internal func asAsyncStream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream(
            bufferingPolicy: .unbounded
        )
        let upstream = self
        let task = Task {
            await upstream.collect { value in
                guard !Task.isCancelled else { return }
                continuation.yield(value)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }
}

extension ThrowingFlow {
    /// Bridges this throwing flow into an `AsyncThrowingStream`. Used
    /// internally by combining operators.
    ///
    /// - Important: The returned stream must be iterated within a structured context.
    internal func asAsyncThrowingStream() -> AsyncThrowingStream<Element, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Element, any Error>.makeStream(
            bufferingPolicy: .unbounded
        )
        let upstream = self
        let task = Task {
            do {
                try await upstream.collect { value in
                    guard !Task.isCancelled else { return }
                    continuation.yield(value)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }
}
