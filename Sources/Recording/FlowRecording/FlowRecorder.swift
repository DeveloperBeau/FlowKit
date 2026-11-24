public import Flow

/// Collects a flow in the background and records every value in order.
///
/// Collection starts when the recorder is created and stops on ``cancel()``
/// or when the recorder is released. The recorder only records and waits. It
/// has no assertions, no timeouts, and no clock, so it can be linked into a
/// host app, a preview target, or a fixture that cannot link `Testing`.
///
/// ```swift
/// let recorder = FlowRecorder(source.changes())
/// source.set(.on)
/// let values = await recorder.values(atLeast: 2) // [.off, .on]
/// recorder.cancel()
/// ```
///
/// The record is unbounded. Every value stays in memory for as long as the
/// recorder lives, so use it in tests and fixtures and not in production code.
public final class FlowRecorder<Element: Sendable>: Sendable {
    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<[Element], Never>
    }

    private struct State {
        var values: [Element] = []
        var isFinished = false
        var failure: (any Error)?
        var waiters: [Int: Waiter] = [:]
        var nextWaiterID = 0
    }

    /// The record itself. The collection task holds this and not the recorder,
    /// so releasing the recorder is what ends the collection.
    private final class Storage: Sendable {
        private let state = Mutex(State())

        var values: [Element] { state.withLock { $0.values } }
        var isFinished: Bool { state.withLock { $0.isFinished } }
        var failure: (any Error)? { state.withLock { $0.failure } }

        func record(_ value: Element) {
            let ready = state.withLock { state -> [(Waiter, [Element])] in
                // A value that arrives after the end is dropped, so the record
                // a caller has already read never grows.
                guard !state.isFinished else { return [] }
                state.values.append(value)
                let count = state.values.count
                let satisfied = state.waiters.filter { $0.value.count <= count }
                for id in satisfied.keys { state.waiters.removeValue(forKey: id) }
                return satisfied.values.map { ($0, state.values) }
            }
            for (waiter, values) in ready { waiter.continuation.resume(returning: values) }
        }

        /// Ends the record and resumes every waiter. Only the first call counts.
        func finish(failure: (any Error)?) {
            let ready = state.withLock { state -> [(Waiter, [Element])] in
                guard !state.isFinished else { return [] }
                state.isFinished = true
                state.failure = failure
                defer { state.waiters = [:] }
                return state.waiters.values.map { ($0, state.values) }
            }
            for (waiter, values) in ready { waiter.continuation.resume(returning: values) }
        }

        func values(atLeast count: Int) async -> [Element] {
            let id = state.withLock { state -> Int in
                state.nextWaiterID += 1
                return state.nextWaiterID
            }
            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<[Element], Never>) in
                    let current = state.withLock { state -> [Element]? in
                        if state.values.count >= count || state.isFinished || Task.isCancelled {
                            return state.values
                        }
                        state.waiters[id] = Waiter(count: count, continuation: continuation)
                        return nil
                    }
                    if let current { continuation.resume(returning: current) }
                }
            } onCancel: {
                let cancelled = state.withLock { state -> (Waiter, [Element])? in
                    state.waiters.removeValue(forKey: id).map { ($0, state.values) }
                }
                if let (waiter, values) = cancelled {
                    waiter.continuation.resume(returning: values)
                }
            }
        }
    }

    private let storage: Storage
    private let task: Task<Void, Never>

    /// Starts collecting `flow` and recording its values.
    public init(_ flow: Flow<Element>) {
        let storage = Storage()
        self.storage = storage
        self.task = Task {
            await flow.collect { storage.record($0) }
            storage.finish(failure: nil)
        }
    }

    /// Starts collecting `flow` and recording its values and its error.
    public init(_ flow: ThrowingFlow<Element>) {
        let storage = Storage()
        self.storage = storage
        self.task = Task {
            do {
                try await flow.collect { storage.record($0) }
                storage.finish(failure: nil)
            } catch {
                storage.finish(failure: error)
            }
        }
    }

    deinit {
        task.cancel()
    }

    /// Everything received so far, in emission order.
    public var values: [Element] { storage.values }

    /// `true` once the flow completed or failed, or the recorder was cancelled.
    public var isFinished: Bool { storage.isFinished }

    /// The error a throwing flow failed with, or `nil` if it has not failed.
    ///
    /// An error the flow throws after ``cancel()`` is not reported.
    public var failure: (any Error)? { storage.failure }

    /// Suspends until at least `count` values were received or the recording ended.
    ///
    /// Returns at once when `count` values are already recorded, and returns
    /// what it has when the flow ends first, when the recorder is cancelled, or
    /// when the waiting task is cancelled. The wait has no deadline. Bound it
    /// from the caller if the flow may stay open without emitting.
    ///
    /// - Parameter count: The number of values to wait for. Zero or less returns at once.
    /// - Returns: Every value received so far, which can be more than `count`.
    public func values(atLeast count: Int) async -> [Element] {
        await storage.values(atLeast: count)
    }

    /// Stops collecting the flow and ends the recording.
    ///
    /// Pending calls to ``values(atLeast:)`` return what was recorded. Values
    /// stay readable afterwards. Calling it again does nothing.
    public func cancel() {
        task.cancel()
        storage.finish(failure: nil)
    }
}
