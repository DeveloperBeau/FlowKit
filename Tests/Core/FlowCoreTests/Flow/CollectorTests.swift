import Testing
import FlowSharedModels
@testable import FlowCore

@Suite("Collector")
struct CollectorTests {
    @Test("emit forwards value to the action closure")
    func emitForwardsValue() async {
        let storage = Mutex<[String]>([])
        let collector = Collector<String> { value in
            storage.withLock { $0.append(value) }
        }
        await collector.emit("hello")
        await collector.emit("world")
        let received = storage.withLock { $0 }
        #expect(received == ["hello", "world"])
    }

    @Test("Collector is Sendable")
    func isSendable() async {
        let storage = Mutex<[Int]>([])
        let collector = Collector<Int> { value in
            storage.withLock { $0.append(value) }
        }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await collector.emit(i)
                }
            }
        }
        let final = storage.withLock { $0.sorted() }
        #expect(final == Array(0..<10))
    }
}
