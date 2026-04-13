import Foundation

internal actor MulticastSubscription<Element: Sendable> {
    private struct Subscriber {
        let continuation: AsyncStream<Element>.Continuation
    }

    private var subscribers: [UUID: Subscriber] = [:]

    init() {}

    var subscriberCount: Int { subscribers.count }

    func makeSubscription() -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .unbounded)
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
