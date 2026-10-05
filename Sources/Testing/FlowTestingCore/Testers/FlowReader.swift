import Foundation
public import Testing
public import FlowCore

/// What a test reads from a flow it is observing, with no deadline anywhere.
///
/// Each read suspends until the flow's own next emission, its completion or its
/// failure resumes it. A wrong value fails the read at the caller's source
/// location. A flow that ends before the value a test is waiting for fails the
/// read and throws ``FlowReaderError/flowEnded``, and keeps failing every later
/// read the same way, because the end is remembered rather than consumed.
/// Nothing here measures time, so a loaded machine cannot turn a correct test
/// into a failing one.
///
/// Get a reader from ``FlowCore/Flow/probing(_:)`` or
/// ``FlowCore/ThrowingFlow/probing(_:)``.
///
/// ## Probing or `test(timeout:)`
///
/// Prefer probing when the test triggers every emission it expects: a read
/// waits for exactly that emission, however long a slow machine takes. Prefer
/// `test(timeout:_:)` when the test must observe a flow that stays quiet for a
/// while, or must bound how long a producer may take, because only a clock can
/// say "nothing arrived within this time".
///
/// ## The limit
///
/// A producer that stays open and never emits again cannot be told apart from a
/// slow one without a clock. Such a read parks until the surrounding test is
/// cancelled, so it is the one shape a reader cannot report by name. Keep
/// producers in tests tied to an action the test itself performs, and assert
/// that nothing else arrives with ``expectNextValue(_:sourceLocation:)`` rather
/// than by sleeping.
public actor FlowReader<Element: Sendable> {
    enum Event {
        case value(Element)
        case completed
        case failed(any Error)
    }

    private var queued: [Event] = []
    private var ending: Event?
    private var waiter: CheckedContinuation<Event, Never>?

    init() {}

    func record(_ event: Event) {
        if case .value = event {} else {
            ending = event
        }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: event)
        } else if case .value = event {
            queued.append(event)
        }
    }

    private func next() async -> Event {
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        if let ending {
            return ending
        }
        return await withCheckedContinuation { waiter = $0 }
    }

    /// The next value the flow emits.
    ///
    /// Records an issue and throws ``FlowReaderError/flowEnded`` if the flow
    /// completes or fails first.
    public func awaitValue(
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Element {
        switch await next() {
        case .value(let value):
            return value
        case .completed:
            Issue.record("expected a value but the flow completed", sourceLocation: sourceLocation)
        case .failed(let error):
            Issue.record("expected a value but the flow failed with \(error)", sourceLocation: sourceLocation)
        }
        throw FlowReaderError.flowEnded
    }

    /// Asserts the next value the flow emits equals `expected`.
    public func expectValue(
        _ expected: Element,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws where Element: Equatable {
        let actual = try await awaitValue(sourceLocation: sourceLocation)
        #expect(actual == expected, sourceLocation: sourceLocation)
    }

    /// Asserts `sentinel` is the next value, so no other value arrived before it.
    ///
    /// This is the clock-free replacement for `expectNoValue(within:)`. Trigger
    /// an emission you know will follow the one you expect nothing from, then
    /// read for it: if anything else was emitted in between, the read fails
    /// naming that value.
    public func expectNextValue(
        _ sentinel: Element,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws where Element: Equatable {
        let actual = try await awaitValue(sourceLocation: sourceLocation)
        #expect(
            actual == sentinel,
            "expected \(sentinel) next but \(actual) arrived first",
            sourceLocation: sourceLocation
        )
    }

    /// Asserts the flow completes without emitting another value or failing.
    public func expectCompletion(
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        switch await next() {
        case .completed:
            return
        case .value(let value):
            Issue.record("expected completion but received value \(value)", sourceLocation: sourceLocation)
            throw FlowReaderError.unexpectedValue
        case .failed(let error):
            Issue.record("expected completion but the flow failed with \(error)", sourceLocation: sourceLocation)
            throw FlowReaderError.flowEnded
        }
    }

    /// Asserts the flow fails with an error `matching` accepts.
    ///
    /// `description` names the expected error in the failure message.
    public func expectError(
        _ description: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        matching: @Sendable (any Error) -> Bool
    ) async throws {
        switch await next() {
        case .failed(let error):
            #expect(
                matching(error),
                "expected an error matching '\(description)' but got \(error)",
                sourceLocation: sourceLocation
            )
        case .value(let value):
            Issue.record(
                "expected an error matching '\(description)' but received \(value)",
                sourceLocation: sourceLocation
            )
            throw FlowReaderError.unexpectedValue
        case .completed:
            Issue.record(
                "expected an error matching '\(description)' but the flow completed",
                sourceLocation: sourceLocation
            )
            throw FlowReaderError.flowEnded
        }
    }

    /// Drops any value the flow emitted that no read consumed.
    public func cancelAndIgnoreRemaining() {
        queued.removeAll()
    }
}

/// Why a ``FlowReader`` read threw.
public enum FlowReaderError: Error, Sendable, Equatable {
    /// The flow completed or failed before the value the read was waiting for.
    case flowEnded
    /// A value arrived where the read expected completion or an error.
    case unexpectedValue
}

extension Flow {
    /// Collects this flow while `block` reads it through a ``FlowReader``, then
    /// stops collecting.
    ///
    /// Reads suspend on the flow's own emissions and carry no deadline. See
    /// ``FlowReader`` for when to prefer this over `test(timeout:_:)`.
    public func probing(
        _ block: (FlowReader<Element>) async throws -> Void
    ) async throws {
        let probe = FlowReader<Element>()
        let collectionTask = Task {
            await self.collect { await probe.record(.value($0)) }
            await probe.record(.completed)
        }
        defer { collectionTask.cancel() }
        try await block(probe)
    }
}

extension ThrowingFlow {
    /// Collects this throwing flow while `block` reads it through a
    /// ``FlowReader``, then stops collecting.
    ///
    /// A failure of the flow is read with ``FlowReader/expectError(_:sourceLocation:matching:)``.
    public func probing(
        _ block: (FlowReader<Element>) async throws -> Void
    ) async throws {
        let probe = FlowReader<Element>()
        let collectionTask = Task {
            do {
                try await self.collect { await probe.record(.value($0)) }
                await probe.record(.completed)
            } catch {
                await probe.record(.failed(error))
            }
        }
        defer { collectionTask.cancel() }
        try await block(probe)
    }
}
