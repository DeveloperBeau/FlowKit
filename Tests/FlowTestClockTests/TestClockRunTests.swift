import Testing
import Foundation
@testable import FlowTestClock

@Suite("TestClock run")
struct TestClockRunTests {
    @Test("run advances to the furthest sleeper's deadline")
    func runAdvancesToFurthest() async throws {
        let clock = TestClock()
        let orderLock = NSLock()
        nonisolated(unsafe) var _woke: [Int] = []

        async let t1: Void = {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(1)), tolerance: nil)
            orderLock.withLock { _woke.append(1) }
        }()

        async let t2: Void = {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(5)), tolerance: nil)
            orderLock.withLock { _woke.append(5) }
        }()

        async let t3: Void = {
            try await clock.sleep(until: TestClock.Instant(offset: .seconds(3)), tolerance: nil)
            orderLock.withLock { _woke.append(3) }
        }()

        try? await Task.sleep(nanoseconds: 20_000_000)
        await clock.run()

        _ = try await (t1, t2, t3)

        let order = orderLock.withLock { _woke }
        #expect(order == [1, 3, 5])
        #expect(clock.now.offset == .seconds(5))
    }

    @Test("run with no sleepers is a no-op")
    func runNoSleepers() async {
        let clock = TestClock()
        await clock.run()
        #expect(clock.now.offset == .zero)
    }
}
