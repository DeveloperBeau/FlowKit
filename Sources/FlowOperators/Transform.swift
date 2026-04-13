public import FlowCore

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
