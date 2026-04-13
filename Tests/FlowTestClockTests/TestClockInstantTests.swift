import Testing
import Foundation
@testable import FlowTestClock

@Suite("TestClock.Instant")
struct TestClockInstantTests {
    @Test("default instant has zero offset")
    func defaultInstant() {
        let instant = TestClock.Instant()
        #expect(instant.offset == .zero)
    }

    @Test("advanced(by:) produces a later instant")
    func advancedBy() {
        let start = TestClock.Instant()
        let later = start.advanced(by: .seconds(5))
        #expect(later.offset == .seconds(5))
    }

    @Test("duration(to:) returns the difference")
    func durationTo() {
        let a = TestClock.Instant(offset: .milliseconds(100))
        let b = TestClock.Instant(offset: .milliseconds(300))
        #expect(a.duration(to: b) == .milliseconds(200))
    }

    @Test("instants compare by offset")
    func comparableInstants() {
        let a = TestClock.Instant(offset: .zero)
        let b = TestClock.Instant(offset: .seconds(1))
        let c = TestClock.Instant(offset: .seconds(2))
        #expect(a < b)
        #expect(b < c)
        #expect(a <= a)
    }
}
