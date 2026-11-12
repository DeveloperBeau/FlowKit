# Async bridge

`Sources/Core/FlowOperators/AsyncSequenceBridge.swift` is the seam between a flow and an `AsyncSequence`. The two sides do not have the same lifetime rules. A flow is cold and can have many collectors. An `AsyncStream` is single-consumer and starts producing when it is created.

## Flow to AsyncStream

`Flow.asAsyncStream()` and `ThrowingFlow.asAsyncThrowingStream()` collect in a child task that starts immediately. Values are buffered with no bound until the consumer takes them. If the producer can outrun the consumer, apply `buffer(size:policy:)` on the flow first.

The stream finishes when the flow completes. A throwing flow's error is rethrown after the values that were emitted before the failure. When the consumer stops iterating, or the consuming task is cancelled, the stream's termination handler cancels the collection task.

The stream has one consumer, like any `AsyncStream`. Iterate it inside structured concurrency.

## AsyncSequence to Flow

`AsyncSequence.asThrowingFlow()` is available when the sequence and its element are `Sendable`. Each collector iterates the sequence itself. A value-type sequence, including the ones AsyncAlgorithms returns, runs again for each collector. A single-consumption sequence such as `AsyncStream` delivers its elements to the first collector only.

`asFlow()` exists when the sequence's `Failure` is `Never`, on the SDKs from the iOS 18, macOS 15, tvOS 18, watchOS 11, and visionOS 2 cycle. On earlier deployment targets the non-failing bridge is `asThrowingFlow()` followed by `catch`.

Cancellation follows the sequence's iterator. A sequence that never suspends and never checks cancellation is not interrupted mid-iteration.

`AsyncSequenceBridge.swift` does not import AsyncAlgorithms. The package dependency is for `zip` and `combineLatest`, which is covered on the [operators](Operators.md) page.
