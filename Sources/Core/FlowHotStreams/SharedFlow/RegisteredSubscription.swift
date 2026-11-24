internal import Foundation
internal import FlowSharedModels

/// A subscriber that `subscribed()` registered before it returned.
///
/// The flow that `subscribed()` returns owns one of these. Releasing that flow
/// releases this object, and `deinit` removes the registration, so a flow that
/// is never collected does not leave a subscriber behind.
internal final class RegisteredSubscription<Element: Sendable>: Sendable {
    /// The values delivered since registration, in order.
    let stream: AsyncStream<Element>

    private let id: UUID
    private let subscription: MulticastSubscription<Element>
    private let hasCollector = Mutex(false)

    init(in subscription: MulticastSubscription<Element>, awaitingReplay: Bool = false) {
        let (id, stream) = subscription.register(awaitingReplay: awaitingReplay)
        self.id = id
        self.stream = stream
        self.subscription = subscription
    }

    deinit {
        subscription.unregister(id: id)
    }

    /// Claims the single collection. Returns `false` to every caller after
    /// the first, because two iterations of one stream would split its values.
    func claimCollection() -> Bool {
        hasCollector.withLock { hasCollector in
            let isFirst = !hasCollector
            hasCollector = true
            return isFirst
        }
    }

    /// Removes the registration and finishes the stream. Values already
    /// buffered can still be read.
    func cancel() {
        subscription.unregister(id: id)
    }
}
