import Foundation

/// Bounds the number of unconsumed values a suspending ``ProducerScope/send(_:)``
/// may have in flight. A sender past `capacity` suspends until the consumer
/// releases a slot or the channel closes.
///
/// Cancellation safety: a suspended sender is identified by a caller-supplied
/// ID so `cancel(id:)` can resume exactly that waiter. When the cancellation
/// handler runs before the waiter registers, the ID is remembered and the
/// registration returns immediately — no continuation is ever left parked.
internal actor SendGate {
    private let capacity: Int
    private var inFlight = 0
    private var closed = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    private var cancelledIDs: Set<UUID> = []

    internal init(capacity: Int) {
        self.capacity = capacity
    }

    /// Acquires a slot, suspending while `capacity` values are unconsumed.
    ///
    /// - Returns: `true` when a slot was granted; `false` when the channel
    ///   closed or the sender was cancelled instead.
    internal func acquire(id: UUID) async -> Bool {
        guard !closed else { return false }
        guard cancelledIDs.remove(id) == nil else { return false }
        if inFlight < capacity {
            inFlight += 1
            return true
        }
        return await withCheckedContinuation { continuation in
            waiters.append((id: id, continuation: continuation))
        }
    }

    /// Wakes the waiter registered under `id` with a refusal, or records the
    /// ID so a not-yet-registered `acquire` refuses immediately.
    internal func cancel(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else {
            cancelledIDs.insert(id)
        }
    }

    /// Frees one slot after the consumer processed a value. The slot transfers
    /// directly to the oldest suspended sender when one is waiting.
    internal func release() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
        } else if inFlight > 0 {
            inFlight -= 1
        }
    }

    /// Closes the gate: every suspended sender and every future `acquire`
    /// resolves to `false`.
    internal func close() {
        closed = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(returning: false)
        }
    }
}
