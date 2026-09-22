import Testing
import FlowCore
import FlowTesting
import FlowSharedModels
@testable import FlowOperators

@Suite("ThrowingFlow operators")
struct ThrowingFlowOperatorTests {
    // MARK: - Transform operators

    @Test("ThrowingFlow.map transforms each value")
    func map() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        try await flow.map { $0 * 10 }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectValue(30)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.map propagates errors from transform")
    func mapError() async throws {
        struct ParseError: Error, Equatable {}
        let flow = ThrowingFlow(of: "1", "bad", "3")
        try await flow.map { s -> Int in
            guard let i = Int(s) else { throw ParseError() }
            return i
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectError(ParseError())
        }
    }

    @Test("ThrowingFlow.compactMap drops nil values")
    func compactMap() async throws {
        let flow = ThrowingFlow(of: "1", "two", "3")
        try await flow.compactMap { Int($0) }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(3)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.filter emits only matching values")
    func filter() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3, 4, 5, 6)
        try await flow.filter { $0.isMultiple(of: 2) }.test { tester in
            try await tester.expectValue(2)
            try await tester.expectValue(4)
            try await tester.expectValue(6)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.transform can fan out")
    func transform() async throws {
        let flow = ThrowingFlow(of: 1, 2)
        try await flow.transform { value, collector in
            try await collector.emit("\(value)a")
            try await collector.emit("\(value)b")
        }.test { tester in
            try await tester.expectValue("1a")
            try await tester.expectValue("1b")
            try await tester.expectValue("2a")
            try await tester.expectValue("2b")
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.prefix takes first N")
    func prefix() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3, 4, 5)
        try await flow.prefix(2).test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.dropFirst skips first N")
    func dropFirst() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3, 4, 5)
        try await flow.dropFirst(3).test { tester in
            try await tester.expectValue(4)
            try await tester.expectValue(5)
            try await tester.expectCompletion()
        }
    }

    @Test("ThrowingFlow.scan accumulates")
    func scan() async throws {
        let flow = ThrowingFlow(of: 1, 2, 3)
        try await flow.scan(0) { $0 + $1 }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(3)
            try await tester.expectValue(6)
            try await tester.expectCompletion()
        }
    }

    // MARK: - Lifecycle operators

    @Test("ThrowingFlow.onStart runs before upstream")
    func onStart() async throws {
        let log = Mutex<[String]>([])
        let flow = ThrowingFlow<Int> { collector in
            log.withLock { $0.append("upstream") }
            try await collector.emit(1)
        }
        try await flow.onStart {
            log.withLock { $0.append("onStart") }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectCompletion()
        }
        #expect(log.withLock { $0 } == ["onStart", "upstream"])
    }

    @Test("ThrowingFlow.onEach runs side-effect")
    func onEach() async throws {
        let observed = Mutex<[Int]>([])
        let flow = ThrowingFlow(of: 10, 20)
        try await flow.onEach { value in
            observed.withLock { $0.append(value) }
        }.test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectCompletion()
        }
        #expect(observed.withLock { $0 } == [10, 20])
    }

    @Test("ThrowingFlow.onCompletion receives nil on success")
    func onCompletionSuccess() async throws {
        let captured = Mutex<Bool?>(nil)
        let flow = ThrowingFlow(of: 1)
        try await flow.onCompletion { error in
            captured.withLock { $0 = (error == nil) }
        }.test { tester in
            try await tester.expectValue(1)
            try await tester.expectCompletion()
        }
        #expect(captured.withLock { $0 } == true)
    }

    @Test("ThrowingFlow.onCompletion receives error on failure")
    func onCompletionError() async throws {
        struct Boom: Error, Equatable {}
        let captured = Mutex<Bool>(false)
        let flow = ThrowingFlow<Int> { _ in throw Boom() }
        try await flow.onCompletion { error in
            captured.withLock { $0 = (error != nil) }
        }.test { tester in
            try await tester.expectError(Boom())
        }
        #expect(captured.withLock { $0 } == true)
    }
}
