import Foundation
import Testing
import FlowSharedModels

/// Internal actor containing the event queue and assertion logic shared
/// between `FlowTester` and `ThrowingFlowTester`.
internal actor FlowTesterBase<Element: Sendable> {
    enum Event: Sendable {
        case value(Element)
        case completion
        case failure(any Error)
    }

    private var recorded: [Event] = []
    /// The active waiter continuation. Stored in a Mutex so the cancellation
    /// handler in `awaitNextEvent` can resume it from outside actor isolation.
    private let waiterBox = Mutex<CheckedContinuation<Event, any Error>?>(nil)

    func recordValue(_ value: Element) {
        let event: Event = .value(value)
        if let waiter = waiterBox.withLock({ w -> CheckedContinuation<Event, any Error>? in
            let c = w; w = nil; return c
        }) {
            waiter.resume(returning: event)
        } else {
            recorded.append(event)
        }
    }

    func recordCompletion() {
        let event: Event = .completion
        if let waiter = waiterBox.withLock({ w -> CheckedContinuation<Event, any Error>? in
            let c = w; w = nil; return c
        }) {
            waiter.resume(returning: event)
        } else {
            recorded.append(event)
        }
    }

    func recordError(_ error: any Error) {
        let event: Event = .failure(error)
        if let waiter = waiterBox.withLock({ w -> CheckedContinuation<Event, any Error>? in
            let c = w; w = nil; return c
        }) {
            waiter.resume(returning: event)
        } else {
            recorded.append(event)
        }
    }

    func awaitNextEvent(within timeout: Duration) async throws -> Event {
        if !recorded.isEmpty {
            return recorded.removeFirst()
        }

        return try await withThrowingTimeout(timeout) { [weak self] in
            guard let self else { throw FlowTestError.timeout }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    Task { [weak self] in
                        await self?.registerWaiter(continuation)
                    }
                }
            } onCancel: { [weak self] in
                // Resume the waiter (if registered) with CancellationError so
                // the continuation is never orphaned.
                let waiter = self?.waiterBox.withLock { w -> CheckedContinuation<Event, any Error>? in
                    let c = w; w = nil; return c
                }
                waiter?.resume(throwing: CancellationError())
            }
        }
    }

    private func registerWaiter(_ continuation: CheckedContinuation<Event, any Error>) {
        // Check if the task was already cancelled before we could register.
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if !recorded.isEmpty {
            let first = recorded.removeFirst()
            continuation.resume(returning: first)
        } else {
            waiterBox.withLock { $0 = continuation }
        }
    }

    func drainUnawaited() -> [Event] {
        let drained = recorded
        recorded.removeAll()
        return drained
    }

    func snapshotValues() -> [Element] {
        recorded.compactMap {
            if case .value(let v) = $0 { return v } else { return nil }
        }
    }
}
