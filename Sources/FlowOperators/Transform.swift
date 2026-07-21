public import FlowCore
import FlowSharedModels

// MARK: - map

extension Flow {
    public func map<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> U
    ) -> Flow<U> {
        Flow<U> { downstream in
            await self.collect { upstreamValue in
                let transformed = await transform(upstreamValue)
                await downstream.emit(transformed)
            }
        }
    }
}

extension Flow {
    /// Transforms each value with a throwing closure, converting this
    /// non-failing flow into a `ThrowingFlow`. This is the explicit bridge
    /// from `Flow` to `ThrowingFlow` described in the `Flow` documentation.
    public func mapThrowing<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> U
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            for await value in self.asAsyncStream() {
                let transformed = try await transform(value)
                try await downstream.emit(transformed)
            }
        }
    }
}

extension ThrowingFlow {
    public func map<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> U
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            try await self.collect { upstreamValue in
                let transformed = try await transform(upstreamValue)
                try await downstream.emit(transformed)
            }
        }
    }
}

// MARK: - compactMap

extension Flow {
    public func compactMap<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> U?
    ) -> Flow<U> {
        Flow<U> { downstream in
            await self.collect { upstreamValue in
                if let transformed = await transform(upstreamValue) {
                    await downstream.emit(transformed)
                }
            }
        }
    }
}

extension ThrowingFlow {
    public func compactMap<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> U?
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            try await self.collect { upstreamValue in
                if let transformed = try await transform(upstreamValue) {
                    try await downstream.emit(transformed)
                }
            }
        }
    }
}

// MARK: - filterIsInstance

extension Flow {
    /// Emits only the elements that are instances of `T`, cast to `T`.
    ///
    /// Sugar over `compactMap { $0 as? T }`, matching Kotlin's
    /// `filterIsInstance<T>()`. The canonical use is demultiplexing a
    /// heterogeneous event stream into per-type flows.
    ///
    /// - Parameter type: The element type to keep. Usually written
    ///   explicitly (`.filterIsInstance(LocationEvent.self)`); inferable
    ///   from context.
    /// - Returns: A flow of the matching elements, in upstream order.
    public func filterIsInstance<T: Sendable>(_ type: T.Type = T.self) -> Flow<T> {
        compactMap { $0 as? T }
    }
}

extension ThrowingFlow {
    /// Emits only the elements that are instances of `T`, cast to `T`.
    ///
    /// Sugar over `compactMap { $0 as? T }`, matching Kotlin's
    /// `filterIsInstance<T>()`. Errors propagate unchanged.
    ///
    /// - Parameter type: The element type to keep. Usually written
    ///   explicitly; inferable from context.
    /// - Returns: A throwing flow of the matching elements, in upstream order.
    public func filterIsInstance<T: Sendable>(_ type: T.Type = T.self) -> ThrowingFlow<T> {
        compactMap { $0 as? T }
    }
}

// MARK: - filter

extension Flow {
    public func filter(
        _ predicate: @escaping @Sendable (Element) async -> Bool
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            await self.collect { value in
                if await predicate(value) {
                    await downstream.emit(value)
                }
            }
        }
    }
}

extension ThrowingFlow {
    public func filter(
        _ predicate: @escaping @Sendable (Element) async throws -> Bool
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            try await self.collect { value in
                if try await predicate(value) {
                    try await downstream.emit(value)
                }
            }
        }
    }
}

// MARK: - transform

extension Flow {
    public func transform<U: Sendable>(
        _ transformation: @escaping @Sendable (Element, Collector<U>) async -> Void
    ) -> Flow<U> {
        Flow<U> { downstream in
            await self.collect { upstreamValue in
                await transformation(upstreamValue, downstream)
            }
        }
    }
}

extension ThrowingFlow {
    public func transform<U: Sendable>(
        _ transformation: @escaping @Sendable (Element, ThrowingCollector<U>) async throws -> Void
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            try await self.collect { upstreamValue in
                try await transformation(upstreamValue, downstream)
            }
        }
    }
}

// MARK: - prefix

extension Flow {
    public func prefix(_ count: Int) -> Flow<Element> {
        Flow<Element> { downstream in
            guard count > 0 else { return }
            let remaining = PrefixCounter(count)
            await self.collect { value in
                let shouldEmit = await remaining.takeIfPositive()
                if shouldEmit {
                    await downstream.emit(value)
                }
            }
        }
    }
}

extension ThrowingFlow {
    public func prefix(_ count: Int) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            guard count > 0 else { return }
            let remaining = PrefixCounter(count)
            try await self.collect { value in
                let shouldEmit = await remaining.takeIfPositive()
                if shouldEmit {
                    try await downstream.emit(value)
                }
            }
        }
    }
}

private actor PrefixCounter {
    private var remaining: Int
    init(_ count: Int) { self.remaining = count }
    func takeIfPositive() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}

// MARK: - dropFirst

extension Flow {
    public func dropFirst(_ count: Int = 1) -> Flow<Element> {
        Flow<Element> { downstream in
            let skipCounter = DropCounter(count)
            await self.collect { value in
                let shouldEmit = await skipCounter.shouldEmit()
                if shouldEmit {
                    await downstream.emit(value)
                }
            }
        }
    }
}

extension ThrowingFlow {
    public func dropFirst(_ count: Int = 1) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let skipCounter = DropCounter(count)
            try await self.collect { value in
                let shouldEmit = await skipCounter.shouldEmit()
                if shouldEmit {
                    try await downstream.emit(value)
                }
            }
        }
    }
}

private actor DropCounter {
    private var remaining: Int
    init(_ count: Int) { self.remaining = count }
    func shouldEmit() -> Bool {
        if remaining > 0 { remaining -= 1; return false }
        return true
    }
}

// MARK: - scan

extension Flow {
    public func scan<Acc: Sendable>(
        _ initial: Acc,
        _ accumulator: @escaping @Sendable (Acc, Element) async -> Acc
    ) -> Flow<Acc> {
        Flow<Acc> { downstream in
            let state = ScanState(initial: initial)
            await self.collect { value in
                let next = await state.advance(with: value, accumulator: accumulator)
                await downstream.emit(next)
            }
        }
    }
}

extension ThrowingFlow {
    public func scan<Acc: Sendable>(
        _ initial: Acc,
        _ accumulator: @escaping @Sendable (Acc, Element) async throws -> Acc
    ) -> ThrowingFlow<Acc> {
        ThrowingFlow<Acc> { downstream in
            let state = ScanState(initial: initial)
            try await self.collect { value in
                let next = try await state.advanceThrowing(with: value, accumulator: accumulator)
                try await downstream.emit(next)
            }
        }
    }
}

private actor ScanState<Acc: Sendable> {
    private var current: Acc
    init(initial: Acc) { self.current = initial }
    func advance<Value: Sendable>(
        with value: Value,
        accumulator: @Sendable (Acc, Value) async -> Acc
    ) async -> Acc {
        current = await accumulator(current, value)
        return current
    }
    func advanceThrowing<Value: Sendable>(
        with value: Value,
        accumulator: @Sendable (Acc, Value) async throws -> Acc
    ) async throws -> Acc {
        current = try await accumulator(current, value)
        return current
    }
}

// MARK: - drop(while:)

extension Flow {
    /// Skips values until `predicate` first returns `false`; that value and
    /// everything after it are emitted.
    public func drop(
        while predicate: @escaping @Sendable (Element) async -> Bool
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let dropping = Mutex(true)
            await self.collect { value in
                if dropping.withLock({ $0 }) {
                    if await predicate(value) { return }
                    dropping.withLock { $0 = false }
                }
                await downstream.emit(value)
            }
        }
    }
}

extension ThrowingFlow {
    /// Skips values until `predicate` first returns `false`; that value and
    /// everything after it are emitted.
    public func drop(
        while predicate: @escaping @Sendable (Element) async throws -> Bool
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let dropping = Mutex(true)
            try await self.collect { value in
                if dropping.withLock({ $0 }) {
                    if try await predicate(value) { return }
                    dropping.withLock { $0 = false }
                }
                try await downstream.emit(value)
            }
        }
    }
}

// MARK: - prefix(while:)

extension Flow {
    /// Emits values while `predicate` returns `true`; the first failing value
    /// and everything after it are ignored.
    public func prefix(
        while predicate: @escaping @Sendable (Element) async -> Bool
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let active = Mutex(true)
            await self.collect { value in
                guard active.withLock({ $0 }) else { return }
                if await predicate(value) {
                    await downstream.emit(value)
                } else {
                    active.withLock { $0 = false }
                }
            }
        }
    }
}

extension ThrowingFlow {
    /// Emits values while `predicate` returns `true`; the first failing value
    /// and everything after it are ignored.
    public func prefix(
        while predicate: @escaping @Sendable (Element) async throws -> Bool
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let active = Mutex(true)
            try await self.collect { value in
                guard active.withLock({ $0 }) else { return }
                if try await predicate(value) {
                    try await downstream.emit(value)
                } else {
                    active.withLock { $0 = false }
                }
            }
        }
    }
}

// MARK: - enumerated

extension Flow {
    /// Emits `(offset, element)` pairs counting from zero, mirroring
    /// `Sequence.enumerated()`.
    public func enumerated() -> Flow<(offset: Int, element: Element)> {
        Flow<(offset: Int, element: Element)> { downstream in
            let counter = Mutex(0)
            await self.collect { value in
                let offset = counter.withLock { count -> Int in
                    defer { count += 1 }
                    return count
                }
                await downstream.emit((offset: offset, element: value))
            }
        }
    }
}

extension ThrowingFlow {
    /// Emits `(offset, element)` pairs counting from zero, mirroring
    /// `Sequence.enumerated()`.
    public func enumerated() -> ThrowingFlow<(offset: Int, element: Element)> {
        ThrowingFlow<(offset: Int, element: Element)> { downstream in
            let counter = Mutex(0)
            try await self.collect { value in
                let offset = counter.withLock { count -> Int in
                    defer { count += 1 }
                    return count
                }
                try await downstream.emit((offset: offset, element: value))
            }
        }
    }
}

// MARK: - scan (no initial value)

extension Flow {
    /// Emits the first value unchanged, then each accumulation of the running
    /// result with the next value. An empty upstream emits nothing.
    public func scan(
        _ accumulator: @escaping @Sendable (Element, Element) async -> Element
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let running = Mutex<Element?>(nil)
            await self.collect { value in
                let next: Element
                if let current = running.withLock({ $0 }) {
                    next = await accumulator(current, value)
                } else {
                    next = value
                }
                running.withLock { $0 = next }
                await downstream.emit(next)
            }
        }
    }
}

extension ThrowingFlow {
    /// Emits the first value unchanged, then each accumulation of the running
    /// result with the next value. An empty upstream emits nothing.
    public func scan(
        _ accumulator: @escaping @Sendable (Element, Element) async throws -> Element
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let running = Mutex<Element?>(nil)
            try await self.collect { value in
                let next: Element
                if let current = running.withLock({ $0 }) {
                    next = try await accumulator(current, value)
                } else {
                    next = value
                }
                running.withLock { $0 = next }
                try await downstream.emit(next)
            }
        }
    }
}

// MARK: - chunks(ofCount:)

extension Flow {
    /// Groups values into arrays of `count` elements, emitting any partial
    /// final chunk on completion. Mirrors Swift Algorithms' `chunks(ofCount:)`.
    public func chunks(ofCount count: Int) -> Flow<[Element]> {
        precondition(count > 0, "chunk size must be positive")
        return Flow<[Element]> { downstream in
            let pending = Mutex<[Element]>([])
            await self.collect { value in
                let full: [Element]? = pending.withLock { chunk in
                    chunk.append(value)
                    guard chunk.count == count else { return nil }
                    defer { chunk.removeAll(keepingCapacity: true) }
                    return chunk
                }
                if let full {
                    await downstream.emit(full)
                }
            }
            let remainder = pending.withLock { $0 }
            if !remainder.isEmpty {
                await downstream.emit(remainder)
            }
        }
    }
}

extension ThrowingFlow {
    /// Groups values into arrays of `count` elements, emitting any partial
    /// final chunk on completion. A failing upstream discards the partial
    /// chunk and rethrows. Mirrors Swift Algorithms' `chunks(ofCount:)`.
    public func chunks(ofCount count: Int) -> ThrowingFlow<[Element]> {
        precondition(count > 0, "chunk size must be positive")
        return ThrowingFlow<[Element]> { downstream in
            let pending = Mutex<[Element]>([])
            try await self.collect { value in
                let full: [Element]? = pending.withLock { chunk in
                    chunk.append(value)
                    guard chunk.count == count else { return nil }
                    defer { chunk.removeAll(keepingCapacity: true) }
                    return chunk
                }
                if let full {
                    try await downstream.emit(full)
                }
            }
            let remainder = pending.withLock { $0 }
            if !remainder.isEmpty {
                try await downstream.emit(remainder)
            }
        }
    }
}
