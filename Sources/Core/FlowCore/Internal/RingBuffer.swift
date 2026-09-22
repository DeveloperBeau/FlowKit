/// A fixed-capacity ring buffer used as the replay cache for `MutableSharedFlow`.
/// When the buffer is full, appending a new element overwrites the oldest one.
///
/// Internal to FlowKit. Not part of the public API. We roll our own rather
/// than depending on `swift-collections.Deque` to keep the dependency graph
/// minimal.
///
/// ## Thread safety
///
/// `RingBuffer` is a `struct` with `mutating` methods, so thread safety is the
/// caller's responsibility. In practice it lives inside an actor
/// (`MutableSharedFlow`), which provides the isolation.
internal struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var head: Int = 0
    private var size: Int = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity >= 0, "RingBuffer capacity must be non-negative")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    var count: Int { size }
    var isFull: Bool { size == capacity }

    mutating func append(_ element: Element) {
        guard capacity > 0 else { return }
        let writeIndex = (head + size) % capacity
        storage[writeIndex] = element
        if isFull {
            head = (head + 1) % capacity
        } else {
            size += 1
        }
    }

    mutating func removeFirst() -> Element? {
        guard size > 0 else { return nil }
        let element = storage[head]
        storage[head] = nil
        head = (head + 1) % capacity
        size -= 1
        return element
    }

    var elements: [Element] {
        var result: [Element] = []
        result.reserveCapacity(size)
        for i in 0..<size {
            if let value = storage[(head + i) % capacity] {
                result.append(value)
            }
        }
        return result
    }
}
