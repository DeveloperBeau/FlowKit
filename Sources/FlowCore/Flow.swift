/// A cold asynchronous stream of non-failing values. The body closure runs
/// each time a collector is attached, and each collector gets its own
/// independent execution.
///
/// ## When to use `Flow` vs `ThrowingFlow`
///
/// Use `Flow` when the stream's source cannot fail: UI state observation,
/// timer ticks, sensor readings, derived state from already-loaded data.
/// Use `ThrowingFlow` when the source can fail (network, database, file I/O).
///
/// The two types are distinct, with no shared protocol and no type erasure, so
/// operators are defined separately on each. Converting between them is
/// explicit: `Flow` has `mapThrowing` to become a `ThrowingFlow`, and
/// `ThrowingFlow` has `catch` to become a non-failing `Flow` after handling
/// errors.
///
/// ## Example: debounced search query stream
///
/// ```swift
/// // From a UI text field binding. The raw value stream never fails.
/// let searchQueries: Flow<String> = Flow(observing: viewModel, \.queryText)
///
/// let searchResults: ThrowingFlow<[Product]> = searchQueries
///     .debounce(for: .milliseconds(300))
///     .removeDuplicates()
///     .filter { !$0.isEmpty }
///     .flatMapLatest { query in productRepository.search(query) }
/// ```
///
/// ## Cold by construction
///
/// A `Flow` is a value-type wrapper around a body closure. The closure is not
/// executed when the flow is created. It runs only when `collect(_:)` is called.
/// Calling `collect` twice runs the body twice, independently. If you need to
/// share a single upstream execution between multiple collectors, convert to
/// a hot stream with `asStateFlow` or `asSharedFlow`.
public struct Flow<Element: Sendable>: Sendable {
    public typealias Body = @Sendable (Collector<Element>) async -> Void

    @usableFromInline
    internal let body: Body

    public init(_ body: @escaping Body) {
        self.body = body
    }

    public func collect(
        _ action: @escaping @Sendable (Element) async -> Void
    ) async {
        await body(Collector(action))
    }
}
