import Foundation

internal actor MulticastSubscription<Element: Sendable> {
    private struct Subscriber {
        let continuation: AsyncStream<Element>.Continuation
    }

    /// The per-subscriber buffering policy. A slow subscriber's buffer is
    /// bounded by this, so a fast emitter conflates or drops for it rather than
    /// letting its buffer grow without bound.
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
    private var subscribers: [UUID: Subscriber] = [:]

    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    var subscriberCount: Int { subscribers.count }

    func makeSubscription() -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        subscribers[id] = Subscriber(continuation: continuation)
        return (id, stream)
    }

    func deliver(_ value: Element) {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(value)
        }
    }

    func deliver(_ value: Element, to id: UUID) {
        subscribers[id]?.continuation.yield(value)
    }

    func unsubscribe(id: UUID) {
        if let subscriber = subscribers.removeValue(forKey: id) {
            subscriber.continuation.finish()
        }
    }

    func finishAll() {
        for subscriber in subscribers.values {
            subscriber.continuation.finish()
        }
        subscribers.removeAll()
    }
}
