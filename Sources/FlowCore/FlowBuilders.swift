extension Flow {
    public init(of values: Element...) {
        self.init { collector in
            for value in values {
                await collector.emit(value)
            }
        }
    }

    public init<S: Sequence & Sendable>(_ sequence: S) where S.Element == Element {
        self.init { collector in
            for element in sequence {
                await collector.emit(element)
            }
        }
    }

    public static var empty: Flow<Element> {
        Flow { _ in }
    }

    public static var never: Flow<Element> {
        Flow { _ in
            // Suspend rather than spin: a yield loop stays runnable and burns
            // a cooperative-pool thread for the flow's whole lifetime.
            // Cancellation wakes the sleep immediately.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }
}

extension Sequence where Element: Sendable, Self: Sendable {
    public func asFlow() -> Flow<Element> {
        Flow(self)
    }
}
