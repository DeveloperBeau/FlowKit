import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("Flow builders")
struct FlowBuildersTests {
    @Test("Flow(of:) emits each variadic value in order")
    func variadicInit() async {
        let flow = Flow(of: "one", "two", "three")
        let received = Mutex<[String]>([])
        await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == ["one", "two", "three"])
    }

    @Test("Flow(sequence:) emits each element in order")
    func sequenceInit() async {
        let flow = Flow([1, 2, 3, 4, 5])
        let received = Mutex<[Int]>([])
        await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [1, 2, 3, 4, 5])
    }

    @Test("Flow.empty completes without emitting")
    func emptyFlow() async {
        let flow = Flow<Int>.empty
        let received = Mutex<[Int]>([])
        await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 }.isEmpty)
    }

    @Test("Flow.never suspends indefinitely until cancelled")
    func neverFlow() async {
        let flow = Flow<Int>.never
        let task = Task {
            await flow.collect { _ in
                Issue.record("never should not emit")
            }
        }
        try? await Task.sleep(for: .seconds(0.01))
        task.cancel()
        await task.value
    }

    @Test("Sequence.asFlow() bridges to a Flow")
    func sequenceAsFlow() async {
        let flow: Flow<Int> = [10, 20, 30].asFlow()
        let received = Mutex<[Int]>([])
        await flow.collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [10, 20, 30])
    }
}
