public import FlowCore

// MARK: - catch

extension ThrowingFlow {
    /// Handles errors from the upstream flow by invoking `handler`, which
    /// can emit zero or more recovery values. The result is a non-throwing
    /// `Flow` — the error is consumed.
    ///
    /// ## Example — falling back to cached data
    ///
    /// ```swift
    /// let articles: Flow<[Article]> = articleAPI.fetchLatest()
    ///     .catch { error, collector in
    ///         let cached = try? await articleDatabase.fetchAll()
    ///         if let cached {
    ///             await collector.emit(cached)
    ///         }
    ///     }
    /// ```
    public func `catch`(
        _ handler: @escaping @Sendable (any Error, Collector<Element>) async -> Void
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            do {
                try await self.collect { value in
                    await downstream.emit(value)
                }
            } catch {
                await handler(error, downstream)
            }
        }
    }
}

// MARK: - retry

extension ThrowingFlow {
    /// Re-executes the flow body up to `maxAttempts` times when an error
    /// occurs. If `shouldRetry` is provided, only retries when it returns
    /// `true` for the thrown error.
    ///
    /// ## Example — retry network fetch up to 3 times
    ///
    /// ```swift
    /// let articles = articleAPI.fetchLatest()
    ///     .retry(3, shouldRetry: { $0 is URLError })
    /// ```
    public func retry(
        _ maxAttempts: Int,
        shouldRetry: (@Sendable (any Error) -> Bool)? = nil
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            var attemptsRemaining = maxAttempts
            while true {
                do {
                    try await self.collect { value in
                        try await downstream.emit(value)
                    }
                    return // completed successfully
                } catch {
                    attemptsRemaining -= 1
                    if attemptsRemaining <= 0 {
                        throw error
                    }
                    if let shouldRetry, !shouldRetry(error) {
                        throw error
                    }
                    // Retry: loop back and re-execute self.collect
                }
            }
        }
    }
}

// MARK: - retryWhen

extension ThrowingFlow {
    /// Re-executes the flow body when the async predicate returns `true`.
    /// The predicate receives the thrown error and the current attempt number
    /// (starting at 1). Enables exponential backoff and conditional retry.
    ///
    /// ## Example — exponential backoff
    ///
    /// ```swift
    /// articleAPI.fetchLatest()
    ///     .retryWhen { error, attempt in
    ///         guard error is URLError, attempt < 5 else { return false }
    ///         try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
    ///         return true
    ///     }
    /// ```
    public func retryWhen(
        _ predicate: @escaping @Sendable (any Error, _ attempt: Int) async -> Bool
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            var attempt = 0
            while true {
                do {
                    try await self.collect { value in
                        try await downstream.emit(value)
                    }
                    return
                } catch {
                    attempt += 1
                    let shouldRetry = await predicate(error, attempt)
                    if !shouldRetry {
                        throw error
                    }
                }
            }
        }
    }
}
