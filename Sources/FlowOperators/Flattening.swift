public import FlowCore

// MARK: - flatMap

extension Flow {
    /// Sequentially collects each inner `Flow` produced by `transform`,
    /// forwarding all emitted values downstream.
    public func flatMap<R: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> Flow<R>
    ) -> Flow<R> {
        Flow<R> { downstream in
            await self.collect { value in
                let inner = await transform(value)
                await inner.collect { innerValue in
                    await downstream.emit(innerValue)
                }
            }
        }
    }
}

extension ThrowingFlow {
    /// Sequentially collects each inner `ThrowingFlow` produced by `transform`,
    /// forwarding all emitted values or errors downstream.
    public func flatMap<R: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> ThrowingFlow<R>
    ) -> ThrowingFlow<R> {
        ThrowingFlow<R> { downstream in
            try await self.collect { value in
                let inner = try await transform(value)
                try await inner.collect { innerValue in
                    try await downstream.emit(innerValue)
                }
            }
        }
    }
}

// MARK: - flatMap(maxConcurrent:)

extension Flow {
    /// Transforms each upstream value into a new `Flow` and collects up to
    /// `maxConcurrent` inner flows in parallel. When the limit is reached,
    /// new inner flows wait for an active one to complete.
    ///
    /// ## Example: parallel image downloads (limited to 3)
    ///
    /// ```swift
    /// let images: Flow<UIImage> = imageURLs
    ///     .flatMap(maxConcurrent: 3) { url in imageLoader.load(url) }
    /// ```
    public func flatMap<U: Sendable>(
        maxConcurrent: Int,
        _ transform: @escaping @Sendable (Element) async -> Flow<U>
    ) -> Flow<U> {
        Flow<U> { downstream in
            // Bridge upstream values into an AsyncStream so we can drive the
            // task group from a single structured context (avoiding inout
            // capture issues under Swift 6 strict concurrency).
            let (upstreamStream, upstreamContinuation) = AsyncStream<Element>.makeStream(
                bufferingPolicy: .unbounded
            )
            let upstream = self
            let producerTask = Task {
                await upstream.collect { value in
                    upstreamContinuation.yield(value)
                }
                upstreamContinuation.finish()
            }
            upstreamContinuation.onTermination = { _ in producerTask.cancel() }

            let semaphore = ConcurrencySemaphore(limit: maxConcurrent)
            await withTaskGroup(of: Void.self) { group in
                for await upstreamValue in upstreamStream {
                    await withTaskCancellationHandler {
                        await semaphore.acquire()
                    } onCancel: {
                        Task { await semaphore.cancelAll() }
                    }
                    guard !Task.isCancelled else { break }
                    group.addTask {
                        let inner = await transform(upstreamValue)
                        await inner.collect { innerValue in
                            await downstream.emit(innerValue)
                        }
                        await semaphore.release()
                    }
                }
                // Wait for all in-flight inner flows to finish
                await group.waitForAll()
            }
            await semaphore.cancelAll()
        }
    }
}

/// Simple actor-based semaphore for limiting concurrent inner flows.
private actor ConcurrencySemaphore {
    private let limit: Int
    private var active: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        active -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            active += 1
            waiter.resume()
        }
    }

    /// Resumes all waiting continuations so they can observe cancellation.
    func cancelAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

// MARK: - flatMapLatest

extension Flow {
    /// Transforms each upstream value into a new `Flow`, cancelling the
    /// previously-active inner flow each time a new upstream value arrives.
    /// Only the most recent inner flow's emissions reach downstream.
    ///
    /// ## Example: search-as-you-type
    ///
    /// ```swift
    /// let searchResults: ThrowingFlow<[Product]> = searchQuery
    ///     .flatMapLatest { query in
    ///         productRepository.search(query)
    ///     }
    /// ```
    ///
    /// ## Performance note
    ///
    /// Each upstream value allocates a new `Task` and cancels the previous
    /// one. For high-frequency sources, pair with `debounce` or `throttle`
    /// upstream to reduce task churn.
    public func flatMapLatest<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> Flow<U>
    ) -> Flow<U> {
        Flow<U> { downstream in
            // Every inner emission is stamped with the generation of the
            // inner flow that produced it and funneled through one FIFO
            // pipeline; the drain task drops values whose generation is no
            // longer current. A superseded inner can therefore never deliver
            // after its replacement, even if it was already suspended inside
            // an emit when it was cancelled.
            let (pipeline, feed) = AsyncStream<(generation: UInt64, value: U)>.makeStream()
            let state = FlatMapLatestState<U>(feed: feed)

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.collect { upstreamValue in
                        let inner = await transform(upstreamValue)
                        await state.switchTo(inner: inner)
                        // Yield so a quick inner can emit before the next
                        // upstream value supersedes it. Best-effort only: a
                        // fast upstream may skip intermediate inners entirely,
                        // matching Kotlin's flatMapLatest.
                        await Task.yield()
                        await Task.yield()
                        await Task.yield()
                    }
                    // Wait for the last inner flow, then close the pipeline.
                    await state.finishAfterCurrent()
                }
                group.addTask {
                    for await stamped in pipeline {
                        guard await state.isCurrent(stamped.generation) else { continue }
                        await downstream.emit(stamped.value)
                        if Task.isCancelled { break }
                    }
                }
                await group.waitForAll()
            }
        }
    }
}

extension ThrowingFlow {
    /// Transforms each upstream value into a new `ThrowingFlow`, cancelling
    /// the previously-active inner flow each time a new upstream value arrives.
    /// Errors from the currently-active inner flow propagate downstream;
    /// errors from a superseded inner are discarded with it.
    public func flatMapLatest<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> ThrowingFlow<U>
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            // Same stamped-pipeline design as the non-throwing overload; see
            // there for the ordering rationale. Inner failures travel through
            // the pipeline too, so only the current generation's error is
            // rethrown.
            let (pipeline, feed) = AsyncStream<(generation: UInt64, event: ThrowingInnerEvent<U>)>.makeStream()
            let state = ThrowingFlatMapLatestState<U>(feed: feed)

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        try await self.collect { upstreamValue in
                            let inner = try await transform(upstreamValue)
                            await state.switchTo(inner: inner)
                            await Task.yield()
                            await Task.yield()
                            await Task.yield()
                        }
                    } catch {
                        // Close the pipeline so the drain task ends, then
                        // surface the upstream (or transform) error.
                        await state.cancelCurrentAndFinish()
                        throw error
                    }
                    await state.finishAfterCurrent()
                }
                group.addTask {
                    for await stamped in pipeline {
                        guard await state.isCurrent(stamped.generation) else { continue }
                        switch stamped.event {
                        case .value(let value):
                            try await downstream.emit(value)
                        case .failure(let error):
                            throw error
                        }
                        if Task.isCancelled { break }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

/// An inner flow's output as it travels the `flatMapLatest` pipeline: a
/// value, or the error that ended the inner flow.
private enum ThrowingInnerEvent<U: Sendable>: Sendable {
    case value(U)
    case failure(any Error)
}

/// Tracks the currently-active inner flow task for `flatMapLatest`. When a
/// new inner flow starts, the previous task is cancelled immediately and its
/// generation goes stale, so the drain task discards anything it still emits.
private actor FlatMapLatestState<U: Sendable> {
    private let feed: AsyncStream<(generation: UInt64, value: U)>.Continuation
    private var currentTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(feed: AsyncStream<(generation: UInt64, value: U)>.Continuation) {
        self.feed = feed
    }

    func switchTo(inner: Flow<U>) {
        currentTask?.cancel()
        generation += 1
        let stamped = generation
        let feed = feed
        currentTask = Task {
            await inner.collect { value in
                feed.yield((generation: stamped, value: value))
            }
        }
    }

    func isCurrent(_ stamped: UInt64) -> Bool {
        stamped == generation
    }

    /// Awaits the active inner task — forwarding cancellation to it, so a
    /// long-running inner cannot outlive or hang a torn-down collection —
    /// then closes the pipeline so the drain task finishes.
    func finishAfterCurrent() async {
        defer { feed.finish() }
        guard let task = currentTask else { return }
        // Cover the already-cancelled path explicitly rather than relying on
        // the handler firing during registration.
        if Task.isCancelled { task.cancel() }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private actor ThrowingFlatMapLatestState<U: Sendable> {
    private let feed: AsyncStream<(generation: UInt64, event: ThrowingInnerEvent<U>)>.Continuation
    private var currentTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(feed: AsyncStream<(generation: UInt64, event: ThrowingInnerEvent<U>)>.Continuation) {
        self.feed = feed
    }

    func switchTo(inner: ThrowingFlow<U>) {
        currentTask?.cancel()
        generation += 1
        let stamped = generation
        let feed = feed
        currentTask = Task {
            do {
                try await inner.collect { value in
                    feed.yield((generation: stamped, event: .value(value)))
                }
            } catch {
                feed.yield((generation: stamped, event: .failure(error)))
            }
        }
    }

    func isCurrent(_ stamped: UInt64) -> Bool {
        stamped == generation
    }

    /// Fail-fast teardown for an upstream error: cancel the inner without
    /// waiting for it and close the pipeline so the drain task ends.
    func cancelCurrentAndFinish() {
        currentTask?.cancel()
        feed.finish()
    }

    /// Awaits the active inner task — forwarding cancellation to it, so a
    /// long-running inner cannot outlive or hang a torn-down collection —
    /// then closes the pipeline so the drain task finishes.
    func finishAfterCurrent() async {
        defer { feed.finish() }
        guard let task = currentTask else { return }
        // Cover the already-cancelled path explicitly rather than relying on
        // the handler firing during registration.
        if Task.isCancelled { task.cancel() }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

// MARK: - mapLatest / transformLatest

extension Flow {
    /// Like `map`, but cancels an in-flight transform when a new upstream
    /// value arrives; only the most recent value's result is emitted.
    public func mapLatest<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async -> U
    ) -> Flow<U> {
        flatMapLatest { value in
            Flow<U> { collector in
                await collector.emit(await transform(value))
            }
        }
    }

    /// Like `transform`, but cancels an in-flight transformation when a new
    /// upstream value arrives.
    public func transformLatest<U: Sendable>(
        _ transformation: @escaping @Sendable (Element, Collector<U>) async -> Void
    ) -> Flow<U> {
        flatMapLatest { value in
            Flow<U> { collector in
                await transformation(value, collector)
            }
        }
    }
}

extension ThrowingFlow {
    /// Like `map`, but cancels an in-flight transform when a new upstream
    /// value arrives; only the most recent value's result is emitted.
    public func mapLatest<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> U
    ) -> ThrowingFlow<U> {
        flatMapLatest { value in
            ThrowingFlow<U> { collector in
                try await collector.emit(try await transform(value))
            }
        }
    }

    /// Like `transform`, but cancels an in-flight transformation when a new
    /// upstream value arrives.
    public func transformLatest<U: Sendable>(
        _ transformation: @escaping @Sendable (Element, ThrowingCollector<U>) async throws -> Void
    ) -> ThrowingFlow<U> {
        flatMapLatest { value in
            ThrowingFlow<U> { collector in
                try await transformation(value, collector)
            }
        }
    }
}
