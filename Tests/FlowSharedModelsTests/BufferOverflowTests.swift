import Testing
@testable import FlowSharedModels

@Suite("BufferOverflow")
struct BufferOverflowTests {
    @Test("all three cases exist and are distinct")
    func allCasesDistinct() {
        let suspend: BufferOverflow = .suspend
        let dropOldest: BufferOverflow = .dropOldest
        let dropLatest: BufferOverflow = .dropLatest

        #expect(suspend != dropOldest)
        #expect(dropOldest != dropLatest)
        #expect(suspend != dropLatest)
    }

    @Test("BufferOverflow is Sendable and Equatable")
    func sendableAndEquatable() {
        let a = BufferOverflow.suspend
        let b = BufferOverflow.suspend
        #expect(a == b)
    }
}
