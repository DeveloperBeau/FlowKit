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
    /// ## Example — parallel image downloads (limited to 3)
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
    /// ## Example — search-as-you-type
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
            let state = FlatMapLatestState<U>()
            await self.collect { upstreamValue in
                let inner = await transform(upstreamValue)
                await state.switchTo(inner: inner, downstream: downstream)
                // Yield to allow a quick inner task to run and emit before the
                // next upstream value arrives and triggers cancellation.
                // Multiple yields are needed to let the inner task traverse the
                // async emit chain (actor hop + downstream collector).
                await Task.yield()
                await Task.yield()
                await Task.yield()
            }
            // Wait for the last inner flow to complete
            await state.awaitCurrentCompletion()
        }
    }
}

extension ThrowingFlow {
    /// Transforms each upstream value into a new `ThrowingFlow`, cancelling
    /// the previously-active inner flow each time a new upstream value arrives.
    public func flatMapLatest<U: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> ThrowingFlow<U>
    ) -> ThrowingFlow<U> {
        ThrowingFlow<U> { downstream in
            let state = ThrowingFlatMapLatestState<U>()
            try await self.collect { upstreamValue in
                let inner = try await transform(upstreamValue)
                await state.switchTo(inner: inner, downstream: downstream)
                await Task.yield()
            }
            try await state.awaitCurrentCompletion()
        }
    }
}

/// Tracks the currently-active inner flow task for `flatMapLatest`. When a
/// new inner flow starts, the previous task is cancelled immediately.
private actor FlatMapLatestState<U: Sendable> {
    private var currentTask: Task<Void, Never>?

    func switchTo(inner: Flow<U>, downstream: Collector<U>) {
        currentTask?.cancel()
        currentTask = Task {
            await inner.collect { value in
                guard !Task.isCancelled else { return }
                await downstream.emit(value)
            }
        }
    }

    func awaitCurrentCompletion() async {
        await currentTask?.value
    }
}

private actor ThrowingFlatMapLatestState<U: Sendable> {
    private var currentTask: Task<Void, any Error>?

    func switchTo(inner: ThrowingFlow<U>, downstream: ThrowingCollector<U>) {
        currentTask?.cancel()
        currentTask = Task {
            try await inner.collect { value in
                guard !Task.isCancelled else { return }
                try await downstream.emit(value)
            }
        }
    }

    func awaitCurrentCompletion() async throws {
        if let task = currentTask {
            try await task.value
        }
    }
}
