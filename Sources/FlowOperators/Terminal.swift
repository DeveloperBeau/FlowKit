public import FlowCore
internal import FlowSharedModels

// MARK: - first

extension Flow {
    /// Returns the first emitted value, or `nil` if the flow completes
    /// without emitting.
    public func first() async -> Element? {
        let result = Mutex<Element?>(nil)
        await self.collect { value in
            result.withLock { if $0 == nil { $0 = value } }
        }
        return result.withLock { $0 }
    }

    /// Returns the first value matching `predicate`, or `nil` if the flow
    /// completes without a match.
    public func first(
        where predicate: @escaping @Sendable (Element) -> Bool
    ) async -> Element? {
        let result = Mutex<Element?>(nil)
        await self.collect { value in
            result.withLock { if $0 == nil && predicate(value) { $0 = value } }
        }
        return result.withLock { $0 }
    }
}

// MARK: - toArray

extension Flow {
    /// Collects all emitted values into an array. Suspends until the flow
    /// completes.
    public func toArray() async -> [Element] {
        let result = Mutex<[Element]>([])
        await self.collect { value in
            result.withLock { $0.append(value) }
        }
        return result.withLock { $0 }
    }
}

// MARK: - reduce

extension Flow {
    /// Reduces all emitted values into a single result using `accumulator`.
    /// Returns `initialResult` if the flow emits nothing.
    public func reduce<Result: Sendable>(
        _ initialResult: Result,
        _ accumulator: @escaping @Sendable (Result, Element) -> Result
    ) async -> Result {
        let result = Mutex<Result>(initialResult)
        await self.collect { value in
            result.withLock { $0 = accumulator($0, value) }
        }
        return result.withLock { $0 }
    }
}

// MARK: - exactlyOne

extension Flow {
    /// Returns the single emitted value. Throws if the flow emits zero
    /// values or more than one value.
    public func exactlyOne() async throws -> Element {
        let state = Mutex<(value: Element?, count: Int)>((nil, 0))
        await self.collect { value in
            state.withLock {
                $0.count += 1
                if $0.count == 1 { $0.value = value }
            }
        }
        let (value, count) = state.withLock { ($0.value, $0.count) }
        guard count == 1, let result = value else {
            throw ExactlyOneError(count: count)
        }
        return result
    }
}

/// Error thrown by `exactlyOne()` when the flow emits zero or multiple values.
public struct ExactlyOneError: Error, Sendable {
    /// The number of values the flow actually emitted.
    public let count: Int
}

// MARK: - collectLatest

extension Flow {
    /// Collects this flow, cancelling the previous `action` invocation each
    /// time a new value arrives. Only the action for the most recent value
    /// runs to completion.
    ///
    /// ## Example: processing only the latest search result
    ///
    /// ```swift
    /// searchResults.collectLatest { results in
    ///     let rendered = await renderResults(results) // cancelled if new results arrive
    ///     await display(rendered)
    /// }
    /// ```
    public func collectLatest(
        _ action: @escaping @Sendable (Element) async -> Void
    ) async {
        let currentTask = Mutex<Task<Void, Never>?>(nil)
        await self.collect { value in
            currentTask.withLock { $0?.cancel() }
            let task = Task { await action(value) }
            currentTask.withLock { $0 = task }
        }
        await currentTask.withLock { $0 }?.value
    }
}
