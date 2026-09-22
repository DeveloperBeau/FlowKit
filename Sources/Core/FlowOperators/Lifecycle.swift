public import FlowCore
import FlowSharedModels

// MARK: - onStart

extension Flow {
    /// Runs `action` once before the upstream flow begins emitting.
    public func onStart(
        _ action: @escaping @Sendable () async -> Void
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            await action()
            await self.collect { value in
                await downstream.emit(value)
            }
        }
    }
}

extension ThrowingFlow {
    public func onStart(
        _ action: @escaping @Sendable () async throws -> Void
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            try await action()
            try await self.collect { value in
                try await downstream.emit(value)
            }
        }
    }
}

// MARK: - onEach

extension Flow {
    /// Runs `action` for each emitted value without transforming the stream.
    public func onEach(
        _ action: @escaping @Sendable (Element) async -> Void
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            await self.collect { value in
                await action(value)
                await downstream.emit(value)
            }
        }
    }
}

extension ThrowingFlow {
    public func onEach(
        _ action: @escaping @Sendable (Element) async throws -> Void
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            try await self.collect { value in
                try await action(value)
                try await downstream.emit(value)
            }
        }
    }
}

// MARK: - onCompletion

extension Flow {
    /// Runs `action` after the flow completes. The `error` parameter is
    /// always `nil` for non-throwing flows.
    public func onCompletion(
        _ action: @escaping @Sendable ((any Error)?) async -> Void
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            await self.collect { value in
                await downstream.emit(value)
            }
            await action(nil)
        }
    }
}

extension ThrowingFlow {
    /// Runs `action` after the flow completes. The `error` parameter is
    /// `nil` on normal completion or the thrown error on failure. Re-throws
    /// after running the action.
    public func onCompletion(
        _ action: @escaping @Sendable ((any Error)?) async -> Void
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            do {
                try await self.collect { value in
                    try await downstream.emit(value)
                }
                await action(nil)
            } catch {
                await action(error)
                throw error
            }
        }
    }
}

// MARK: - onEmpty

extension Flow {
    /// Runs `handler` with the downstream collector if the flow completes
    /// without emitting, allowing fallback values to be emitted in its place.
    public func onEmpty(
        _ handler: @escaping @Sendable (Collector<Element>) async -> Void
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let emitted = Mutex(false)
            await self.collect { value in
                emitted.withLock { $0 = true }
                await downstream.emit(value)
            }
            if !emitted.withLock({ $0 }) {
                await handler(downstream)
            }
        }
    }
}

extension ThrowingFlow {
    /// Runs `handler` with the downstream collector if the flow completes
    /// normally without emitting. A failing upstream rethrows instead.
    public func onEmpty(
        _ handler: @escaping @Sendable (ThrowingCollector<Element>) async throws -> Void
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let emitted = Mutex(false)
            try await self.collect { value in
                emitted.withLock { $0 = true }
                try await downstream.emit(value)
            }
            if !emitted.withLock({ $0 }) {
                try await handler(downstream)
            }
        }
    }
}
