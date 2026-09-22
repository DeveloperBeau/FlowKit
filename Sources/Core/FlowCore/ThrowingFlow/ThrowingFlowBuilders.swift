extension ThrowingFlow {
    public init(of values: Element...) {
        self.init { collector in
            for value in values {
                try await collector.emit(value)
            }
        }
    }

    public init<S: Sequence & Sendable>(_ sequence: S) where S.Element == Element {
        self.init { collector in
            for element in sequence {
                try await collector.emit(element)
            }
        }
    }

    public static var empty: ThrowingFlow<Element> {
        ThrowingFlow { _ in }
    }
}

extension Sequence where Element: Sendable, Self: Sendable {
    public func asThrowingFlow() -> ThrowingFlow<Element> {
        ThrowingFlow(self)
    }
}
