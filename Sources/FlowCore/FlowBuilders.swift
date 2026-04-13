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
            while !Task.isCancelled {
                await Task.yield()
            }
        }
    }
}

extension Sequence where Element: Sendable, Self: Sendable {
    public func asFlow() -> Flow<Element> {
        Flow(self)
    }
}
