import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("ThrowingFlow builders")
struct ThrowingFlowBuildersTests {
    @Test("ThrowingFlow(of:) emits each variadic value in order")
    func variadicInit() async throws {
        let flow = ThrowingFlow(of: "a", "b", "c")
        let received = Mutex<[String]>([])
        try await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == ["a", "b", "c"])
    }

    @Test("ThrowingFlow(sequence:) emits each element in order")
    func sequenceInit() async throws {
        let flow = ThrowingFlow([10, 20, 30])
        let received = Mutex<[Int]>([])
        try await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [10, 20, 30])
    }

    @Test("ThrowingFlow.empty completes without emitting")
    func emptyFlow() async throws {
        let flow = ThrowingFlow<Int>.empty
        let received = Mutex<[Int]>([])
        try await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 }.isEmpty)
    }

    @Test("Sequence.asThrowingFlow() bridges to a ThrowingFlow")
    func sequenceAsThrowingFlow() async throws {
        let flow: ThrowingFlow<Int> = [100, 200].asThrowingFlow()
        let received = Mutex<[Int]>([])
        try await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [100, 200])
    }
}
