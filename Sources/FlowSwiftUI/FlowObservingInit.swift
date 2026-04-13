#if canImport(Observation)
public import Observation
public import FlowCore

extension Flow where Element: Sendable {
    /// Creates a flow that emits values from an `@Observable` object's key
    /// path. Internally uses `withObservationTracking` to re-observe on
    /// every change.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    public init<Root: Observable & AnyObject & Sendable, KP: KeyPath<Root, Element> & Sendable>(
        observing root: Root,
        _ keyPath: KP
    ) where Element: Equatable {
        self.init { collector in
            var previous: Element?
            for await value in _observationStream(of: root, keyPath: keyPath) {
                if value != previous {
                    previous = value
                    await collector.emit(value)
                }
            }
        }
    }
}

/// Helper that produces an `AsyncStream` of values driven by `withObservationTracking`.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
private func _observationStream<Root: Observable & AnyObject & Sendable, Value: Sendable, KP: KeyPath<Root, Value> & Sendable>(
    of root: Root,
    keyPath: KP
) -> AsyncStream<Value> {
    AsyncStream { continuation in
        @Sendable func observe() {
            let value = withObservationTracking {
                root[keyPath: keyPath]
            } onChange: {
                Task { @MainActor in
                    observe()
                }
            }
            continuation.yield(value)
        }
        observe()
    }
}
#endif
