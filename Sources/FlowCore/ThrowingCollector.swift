/// Opaque type passed to a `ThrowingFlow` body closure. The flow body calls
/// `emit(_:)` to push values downstream; downstream operators and the final
/// collector decide what to do with each value.
///
/// ## Why a struct, not a protocol
///
/// `ThrowingCollector` is a simple `struct` wrapping an action closure, not
/// a protocol. This lets flow operators compose as trivial closure
/// transformations without generic ceremony or existential overhead.
///
/// ## Usage
///
/// You don't construct a `ThrowingCollector` directly — it's given to you
/// inside a `ThrowingFlow` body closure:
///
/// ```swift
/// let articles = ThrowingFlow<Article> { collector in
///     let response = try await urlSession.data(from: articlesURL)
///     let decoded = try JSONDecoder().decode([Article].self, from: response.0)
///     for article in decoded {
///         try await collector.emit(article)
///     }
/// }
/// ```
public struct ThrowingCollector<Element: Sendable>: Sendable {
    @usableFromInline
    internal let action: @Sendable (Element) async throws -> Void

    internal init(_ action: @escaping @Sendable (Element) async throws -> Void) {
        self.action = action
    }

    /// Pushes `value` downstream. Suspends until downstream has processed the
    /// value (or throws if downstream throws).
    @inlinable
    public func emit(_ value: Element) async throws {
        try await action(value)
    }
}
