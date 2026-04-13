import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("Flow")
struct FlowTests {
    @Test("collect invokes the body closure with a Collector")
    func collectInvokesBody() async {
        let flow = Flow<Int> { collector in
            await collector.emit(10)
            await collector.emit(20)
            await collector.emit(30)
        }
        let storage = Mutex<[Int]>([])
        await flow.collect { value in
            storage.withLock { $0.append(value) }
        }
        let received = storage.withLock { $0 }
        #expect(received == [10, 20, 30])
    }

    @Test("empty flow body yields no values")
    func emptyBodyYieldsNothing() async {
        let flow = Flow<String> { _ in }
        let storage = Mutex<[String]>([])
        await flow.collect { value in
            storage.withLock { $0.append(value) }
        }
        let received = storage.withLock { $0 }
        #expect(received.isEmpty)
    }

    @Test("Flow is Sendable and can be collected from a detached task")
    func isSendable() async {
        let flow = Flow<Int> { collector in
            await collector.emit(99)
        }
        let storage = Mutex(0)
        let received: Int = await Task.detached {
            await flow.collect { value in
                storage.withLock { $0 = value }
            }
            return storage.withLock { $0 }
        }.value
        #expect(received == 99)
    }

    @Test("collecting twice runs the body twice (cold semantics)")
    func coldSemantics() async {
        let invocationCount = Mutex(0)
        let flow = Flow<Int> { collector in
            invocationCount.withLock { $0 += 1 }
            await collector.emit(1)
        }
        await flow.collect { _ in }
        await flow.collect { _ in }
        let count = invocationCount.withLock { $0 }
        #expect(count == 2)
    }
}
