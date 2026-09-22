import Testing
@testable import FlowSharedModels

@Suite("FlowTestError")
struct FlowTestErrorTests {
    @Test("timeout case exists and conforms to Error")
    func timeoutCase() {
        let error: any Error = FlowTestError.timeout
        #expect(error is FlowTestError)
    }

    @Test("unexpectedCompletion case exists")
    func unexpectedCompletion() {
        let error: FlowTestError = .unexpectedCompletion
        #expect(error == .unexpectedCompletion)
    }

    @Test("unexpectedValue case exists")
    func unexpectedValue() {
        let error: FlowTestError = .unexpectedValue
        #expect(error == .unexpectedValue)
    }

    @Test("FlowTestError is Sendable and Equatable")
    func sendableAndEquatable() {
        let a = FlowTestError.timeout
        let b = FlowTestError.timeout
        #expect(a == b)
        #expect(a != .unexpectedValue)
    }
}
