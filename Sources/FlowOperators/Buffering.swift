public import FlowCore
public import FlowSharedModels

// MARK: - buffer

extension Flow {
    /// Buffers upstream values with the given size and overflow policy.
    /// When the buffer is full:
    /// - `.suspend` — suspends the emitter using `CheckedContinuation` until
    ///   space is available (true backpressure via `SuspendingBuffer` actor).
    /// - `.dropOldest` — discards the oldest buffered value.
    /// - `.dropLatest` — discards the incoming value.
    public func buffer(size: Int, policy: BufferOverflow) -> Flow<Element> {
        Flow<Element> { downstream in
            switch policy {
            case .suspend:
                // True backpressure: emitter suspends until the consumer
                // processes a slot, using a custom actor-based buffer.
                let buf = SuspendingBuffer<Element>(capacity: size)
                let stream = buf.makeStream()
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await self.collect { value in
                            await buf.enqueue(value)
                        }
                        await buf.finish()
                    }
                    group.addTask {
                        for await value in stream {
                            await downstream.emit(value)
                            if Task.isCancelled { break }
                        }
                    }
                    await group.waitForAll()
                }

            case .dropOldest:
                let (stream, continuation) = AsyncStream<Element>.makeStream(
                    bufferingPolicy: .bufferingNewest(size)
                )
                let collectTask = Task {
                    await self.collect { value in continuation.yield(value) }
                    continuation.finish()
                }
                for await value in stream {
                    await downstream.emit(value)
                    if Task.isCancelled { break }
                }
                collectTask.cancel()

            case .dropLatest:
                let (stream, continuation) = AsyncStream<Element>.makeStream(
                    bufferingPolicy: .bufferingOldest(size)
                )
                let collectTask = Task {
                    await self.collect { value in continuation.yield(value) }
                    continuation.finish()
                }
                for await value in stream {
                    await downstream.emit(value)
                    if Task.isCancelled { break }
                }
                collectTask.cancel()
            }
        }
    }
}

/// Actor-based bounded buffer that suspends the producer via
/// `CheckedContinuation` when full, providing true backpressure for
/// `buffer(size:policy: .suspend)`.
private actor SuspendingBuffer<Element: Sendable> {
    private let capacity: Int
    private var items: [Element] = []
    private var producerWaiters: [CheckedContinuation<Void, Never>] = []
    private var consumerWaiters: [CheckedContinuation<Element?, Never>] = []
    private var finished = false

    init(capacity: Int) { self.capacity = capacity }

    nonisolated func makeStream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            Task {
                while true {
                    if let value = await self.dequeue() {
                        continuation.yield(value)
                    } else {
                        continuation.finish()
                        break
                    }
                }
            }
        }
    }

    func enqueue(_ value: Element) async {
        if items.count >= capacity {
            await withCheckedContinuation { continuation in
                producerWaiters.append(continuation)
            }
        }
        items.append(value)
        if let waiter = consumerWaiters.first {
            consumerWaiters.removeFirst()
            let v = items.removeFirst()
            resumeProducerIfNeeded()
            waiter.resume(returning: v)
        }
    }

    func dequeue() async -> Element? {
        if !items.isEmpty {
            let value = items.removeFirst()
            resumeProducerIfNeeded()
            return value
        }
        if finished { return nil }
        return await withCheckedContinuation { continuation in
            consumerWaiters.append(continuation)
        }
    }

    func finish() {
        finished = true
        for waiter in consumerWaiters { waiter.resume(returning: nil) }
        consumerWaiters.removeAll()
    }

    private func resumeProducerIfNeeded() {
        guard items.count < capacity, let waiter = producerWaiters.first else { return }
        producerWaiters.removeFirst()
        waiter.resume()
    }
}

// MARK: - keepingLatest

extension Flow {
    /// Drops intermediate values when the collector can't keep up, keeping
    /// only the most recent value. Equivalent to `buffer(size: 1, policy: .dropOldest)`.
    ///
    /// ## Example — fast sensor data with slow UI updates
    ///
    /// ```swift
    /// let latestReading: Flow<SensorReading> = rawSensorData
    ///     .keepingLatest()
    /// ```
    public func keepingLatest() -> Flow<Element> {
        buffer(size: 1, policy: .dropOldest)
    }
}
