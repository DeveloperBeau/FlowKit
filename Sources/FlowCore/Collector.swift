/// Opaque type passed to a `Flow` body closure. The flow body calls `emit(_:)`
/// to push values downstream. Unlike `ThrowingCollector`, `Collector` cannot
/// fail. Use this type when the upstream source is guaranteed not to throw.
///
/// ## Implementation note
///
/// `Collector` is implemented as a thin wrapper over `ThrowingCollector`. The
/// non-throwing contract is enforced at the type level: the action closure
/// passed to `Collector.init` cannot throw, so the wrapped `ThrowingCollector`
/// can never throw from `emit`. The `try!` in `emit` is provably safe.
///
/// This design eliminates duplicated subscription/cancellation logic. Every
/// internal helper works on `ThrowingCollector`, and the non-throwing version
/// is a 5-line wrapper.
public struct Collector<Element: Sendable>: Sendable {
    @usableFromInline
    internal let throwing: ThrowingCollector<Element>

    internal init(_ action: @escaping @Sendable (Element) async -> Void) {
        self.throwing = ThrowingCollector { value in
            await action(value)
        }
    }

    /// Pushes `value` downstream. Suspends until downstream has processed
    /// the value.
    @inlinable
    public func emit(_ value: Element) async {
        try! await throwing.emit(value)
    }
}
