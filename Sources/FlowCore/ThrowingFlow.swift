/// A cold asynchronous stream of values that may fail with an error. Cold by
/// construction — the body closure runs each time a collector is attached.
///
/// ## When to use `ThrowingFlow` vs `Flow`
///
/// Use `ThrowingFlow` when the stream's source can fail: network calls,
/// database queries, file I/O, any operation that throws. Use the non-throwing
/// `Flow` for streams derived from pure state or guaranteed-non-failing sources
/// (UI state observation, timer ticks, sensor readings).
///
/// ## Example — offline-first article list
///
/// ```swift
/// let articles: ThrowingFlow<[Article]> = ThrowingFlow { collector in
///     // Emit cached articles first so the UI has something to show
///     let cached = try await articleDatabase.fetchAll()
///     try await collector.emit(cached)
///
///     // Then fetch fresh articles from the network
///     let fresh = try await articleAPI.fetchLatest()
///     try await articleDatabase.upsert(fresh)
///     try await collector.emit(fresh)
/// }
///
/// try await articles
///     .catch { error, _ in
///         // fall back to cached data on network failure
///     }
///     .collect { displayArticles in
///         articleListView.display(displayArticles)
///     }
/// ```
public struct ThrowingFlow<Element: Sendable>: Sendable {
    public typealias Body = @Sendable (ThrowingCollector<Element>) async throws -> Void

    @usableFromInline
    internal let body: Body

    public init(_ body: @escaping Body) {
        self.body = body
    }

    public func collect(
        _ action: @escaping @Sendable (Element) async throws -> Void
    ) async throws {
        try await body(ThrowingCollector(action))
    }
}
