public import FlowCore
internal import AsyncAlgorithms

// MARK: - zip

extension Flow {
    /// Pairs each element from this flow with the corresponding element from
    /// `other`, emitting tuples. Completes when either flow completes.
    /// Matches `Sequence.zip` semantics: positional pairing, not combinatorial.
    ///
    /// ## Example: pairing questions with answers
    ///
    /// ```swift
    /// let qa: Flow<(Question, Answer)> = questions.zip(answers)
    /// ```
    public func zip<U: Sendable>(
        _ other: Flow<U>
    ) -> Flow<(Element, U)> {
        Flow<(Element, U)> { downstream in
            let stream1 = self.asAsyncStream()
            let stream2 = other.asAsyncStream()
            for await (a, b) in AsyncAlgorithms.zip(stream1, stream2) {
                await downstream.emit((a, b))
                if Task.isCancelled { break }
            }
        }
    }

    /// Pairs each element with the corresponding element from `other` and
    /// applies `transform` to each pair.
    public func zip<U: Sendable, R: Sendable>(
        _ other: Flow<U>,
        _ transform: @escaping @Sendable (Element, U) async -> R
    ) -> Flow<R> {
        Flow<R> { downstream in
            let stream1 = self.asAsyncStream()
            let stream2 = other.asAsyncStream()
            for await (a, b) in AsyncAlgorithms.zip(stream1, stream2) {
                let result = await transform(a, b)
                await downstream.emit(result)
                if Task.isCancelled { break }
            }
        }
    }
}

extension ThrowingFlow {
    /// Pairs each element from this throwing flow with the corresponding
    /// element from `other`, emitting tuples. Uses `asAsyncThrowingStream()`
    /// to bridge both flows. Completes when either flow completes; propagates
    /// errors from either side.
    public func zip<U: Sendable>(
        _ other: ThrowingFlow<U>
    ) -> ThrowingFlow<(Element, U)> {
        ThrowingFlow<(Element, U)> { downstream in
            let stream1 = self.asAsyncThrowingStream()
            let stream2 = other.asAsyncThrowingStream()
            for try await (a, b) in AsyncAlgorithms.zip(stream1, stream2) {
                try await downstream.emit((a, b))
                if Task.isCancelled { break }
            }
        }
    }
}

// MARK: - combineLatest

extension Flow {
    /// Combines this flow with `other`, emitting a tuple of the latest values
    /// whenever either flow emits. No values are emitted until both flows have
    /// emitted at least once. Completes when both flows complete.
    ///
    /// ## Example: form validation
    ///
    /// ```swift
    /// let isValid: Flow<Bool> = username.combineLatest(password) { user, pass in
    ///     !user.isEmpty && pass.count >= 8
    /// }
    /// ```
    public func combineLatest<U: Sendable>(
        _ other: Flow<U>
    ) -> Flow<(Element, U)> {
        Flow<(Element, U)> { downstream in
            let stream1 = self.asAsyncStream()
            let stream2 = other.asAsyncStream()
            for await (a, b) in AsyncAlgorithms.combineLatest(stream1, stream2) {
                await downstream.emit((a, b))
                if Task.isCancelled { break }
            }
        }
    }

    /// Combines this flow with `other` and applies `transform` to each
    /// latest-value pair.
    public func combineLatest<U: Sendable, R: Sendable>(
        _ other: Flow<U>,
        _ transform: @escaping @Sendable (Element, U) async -> R
    ) -> Flow<R> {
        Flow<R> { downstream in
            let stream1 = self.asAsyncStream()
            let stream2 = other.asAsyncStream()
            for await (a, b) in AsyncAlgorithms.combineLatest(stream1, stream2) {
                let result = await transform(a, b)
                await downstream.emit(result)
                if Task.isCancelled { break }
            }
        }
    }
}

extension ThrowingFlow {
    /// Combines this throwing flow with `other`, emitting a tuple of the
    /// latest values whenever either flow emits. Errors from either side
    /// propagate downstream. Uses `asAsyncThrowingStream()` for bridging.
    public func combineLatest<U: Sendable>(
        _ other: ThrowingFlow<U>
    ) -> ThrowingFlow<(Element, U)> {
        ThrowingFlow<(Element, U)> { downstream in
            let stream1 = self.asAsyncThrowingStream()
            let stream2 = other.asAsyncThrowingStream()
            for try await (a, b) in AsyncAlgorithms.combineLatest(stream1, stream2) {
                try await downstream.emit((a, b))
                if Task.isCancelled { break }
            }
        }
    }
}

// MARK: - merge

extension Flow {
    /// Merges emissions from multiple flows into a single flow. Values
    /// interleave based on emission timing. Completes when all input flows
    /// complete.
    ///
    /// ## Example: combining multiple event sources
    ///
    /// ```swift
    /// let allEvents: Flow<AppEvent> = Flow.merge(
    ///     networkEvents,
    ///     userInputEvents,
    ///     timerEvents
    /// )
    /// ```
    public static func merge(_ flows: Flow<Element>...) -> Flow<Element> {
        merge(flows)
    }

    /// Merges an array of flows into a single flow.
    public static func merge(_ flows: [Flow<Element>]) -> Flow<Element> {
        Flow<Element> { downstream in
            await withTaskGroup(of: Void.self) { group in
                for flow in flows {
                    group.addTask {
                        await flow.collect { value in
                            await downstream.emit(value)
                        }
                    }
                }
            }
        }
    }
}

extension ThrowingFlow {
    /// Merges emissions from multiple throwing flows into a single flow.
    /// Values interleave based on emission timing. The first error thrown
    /// by any flow propagates downstream. Completes when all input flows
    /// complete.
    public static func merge(_ flows: ThrowingFlow<Element>...) -> ThrowingFlow<Element> {
        merge(flows)
    }

    /// Merges an array of throwing flows into a single throwing flow.
    public static func merge(_ flows: [ThrowingFlow<Element>]) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for flow in flows {
                    group.addTask {
                        try await flow.collect { value in
                            try await downstream.emit(value)
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

// MARK: - combineLatest (higher arity)

extension Flow {
    /// Combines three flows, emitting the latest triple whenever any of them
    /// emits. Emission starts once every flow has produced a value.
    public func combineLatest<U: Sendable, V: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>
    ) -> Flow<(Element, U, V)> {
        Flow<(Element, U, V)> { downstream in
            let stream1 = self.asAsyncStream()
            let stream2 = second.asAsyncStream()
            let stream3 = third.asAsyncStream()
            for await (a, b, c) in AsyncAlgorithms.combineLatest(stream1, stream2, stream3) {
                await downstream.emit((a, b, c))
                if Task.isCancelled { break }
            }
        }
    }

    /// Combines three flows and applies `transform` to each latest triple.
    public func combineLatest<U: Sendable, V: Sendable, R: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>,
        _ transform: @escaping @Sendable (Element, U, V) async -> R
    ) -> Flow<R> {
        combineLatest(second, third).map { await transform($0.0, $0.1, $0.2) }
    }

    /// Combines four flows, emitting the latest tuple whenever any of them
    /// emits. Emission starts once every flow has produced a value.
    public func combineLatest<U: Sendable, V: Sendable, W: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>,
        _ fourth: Flow<W>
    ) -> Flow<(Element, U, V, W)> {
        combineLatest(second, third)
            .combineLatest(fourth) { triple, d in
                (triple.0, triple.1, triple.2, d)
            }
    }

    /// Combines four flows and applies `transform` to each latest tuple.
    public func combineLatest<U: Sendable, V: Sendable, W: Sendable, R: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>,
        _ fourth: Flow<W>,
        _ transform: @escaping @Sendable (Element, U, V, W) async -> R
    ) -> Flow<R> {
        combineLatest(second, third, fourth).map { await transform($0.0, $0.1, $0.2, $0.3) }
    }

    /// Combines five flows, emitting the latest tuple whenever any of them
    /// emits. Emission starts once every flow has produced a value.
    public func combineLatest<U: Sendable, V: Sendable, W: Sendable, X: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>,
        _ fourth: Flow<W>,
        _ fifth: Flow<X>
    ) -> Flow<(Element, U, V, W, X)> {
        combineLatest(second, third)
            .combineLatest(fourth, fifth) { triple, d, e in
                (triple.0, triple.1, triple.2, d, e)
            }
    }

    /// Combines five flows and applies `transform` to each latest tuple.
    public func combineLatest<U: Sendable, V: Sendable, W: Sendable, X: Sendable, R: Sendable>(
        _ second: Flow<U>,
        _ third: Flow<V>,
        _ fourth: Flow<W>,
        _ fifth: Flow<X>,
        _ transform: @escaping @Sendable (Element, U, V, W, X) async -> R
    ) -> Flow<R> {
        combineLatest(second, third, fourth, fifth).map { await transform($0.0, $0.1, $0.2, $0.3, $0.4) }
    }
}

extension ThrowingFlow {
    /// Combines three throwing flows, emitting the latest triple whenever any
    /// of them emits. Errors from any side propagate downstream.
    public func combineLatest<U: Sendable, V: Sendable>(
        _ second: ThrowingFlow<U>,
        _ third: ThrowingFlow<V>
    ) -> ThrowingFlow<(Element, U, V)> {
        ThrowingFlow<(Element, U, V)> { downstream in
            let stream1 = self.asAsyncThrowingStream()
            let stream2 = second.asAsyncThrowingStream()
            let stream3 = third.asAsyncThrowingStream()
            for try await (a, b, c) in AsyncAlgorithms.combineLatest(stream1, stream2, stream3) {
                try await downstream.emit((a, b, c))
                if Task.isCancelled { break }
            }
        }
    }

    /// Combines three throwing flows and applies `transform` to each latest
    /// triple.
    public func combineLatest<U: Sendable, V: Sendable, R: Sendable>(
        _ second: ThrowingFlow<U>,
        _ third: ThrowingFlow<V>,
        _ transform: @escaping @Sendable (Element, U, V) async throws -> R
    ) -> ThrowingFlow<R> {
        combineLatest(second, third).map { try await transform($0.0, $0.1, $0.2) }
    }
}
