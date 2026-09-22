public import FlowCore

// MARK: - Flow → AsyncSequence

extension Flow {
    /// Bridges this cold flow into an `AsyncStream`, so it can be consumed
    /// with `for await` or handed to any `AsyncSequence`-based API such as
    /// swift-async-algorithms.
    ///
    /// The flow is collected in a child task that starts immediately; the
    /// stream finishes when the flow completes, and the collection is
    /// cancelled when the stream's consumer stops iterating or is cancelled.
    ///
    /// Values are buffered without bound until consumed. If the producer can
    /// outrun the consumer, apply ``buffer(size:policy:)`` upstream to pick a
    /// bounded policy first.
    ///
    /// - Important: The returned stream must be iterated within a structured
    ///   context, and — like any `AsyncStream` — supports a single consumer.
    public func asAsyncStream() -> AsyncStream<Element> {
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
    /// Bridges this throwing flow into an `AsyncThrowingStream`. The flow's
    /// error, if any, is rethrown to the stream's consumer after all values
    /// emitted before the failure.
    ///
    /// Buffering and cancellation behave as in ``Flow/asAsyncStream()``.
    ///
    /// - Important: The returned stream must be iterated within a structured
    ///   context, and — like any `AsyncThrowingStream` — supports a single
    ///   consumer.
    public func asAsyncThrowingStream() -> AsyncThrowingStream<Element, any Error> {
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

// MARK: - AsyncSequence → Flow

extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Bridges any `AsyncSequence` into a ``ThrowingFlow``, connecting
    /// `URLSession` bytes, `NotificationCenter` notifications,
    /// swift-async-algorithms results, and other async sequences to Flow
    /// operators.
    ///
    /// Each collector iterates the sequence independently. Whether that gives
    /// cold semantics depends on the sequence: a value-type sequence like
    /// those from swift-async-algorithms replays for each collector, but a
    /// single-consumption sequence such as `AsyncStream` delivers its
    /// elements to the first collector only.
    ///
    /// Cancellation is cooperative: it propagates through the sequence's own
    /// iterator, so a sequence that never suspends nor checks cancellation
    /// will not be interrupted mid-iteration.
    public func asThrowingFlow() -> ThrowingFlow<Element> {
        ThrowingFlow { collector in
            for try await element in self {
                try await collector.emit(element)
            }
        }
    }
}

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Element: Sendable, Failure == Never {
    /// Bridges a non-failing `AsyncSequence` into a ``Flow``.
    ///
    /// Available where the sequence's typed `Failure` is `Never` (SDKs from
    /// the iOS 18 cycle onward). On earlier deployment targets, use
    /// ``asThrowingFlow()`` and `catch` if a non-failing flow is required.
    ///
    /// Iteration semantics match ``asThrowingFlow()``: each collector
    /// iterates the sequence independently, and single-consumption sequences
    /// deliver to the first collector only.
    public func asFlow() -> Flow<Element> {
        Flow { collector in
            for await element in self {
                await collector.emit(element)
            }
        }
    }
}
