import Testing
import Foundation
import FlowSharedModels
@testable import FlowTestingCore

@Suite("TimeoutHelpers")
struct TimeoutHelpersTests {
    @Test("withThrowingTimeout returns the body's value on success")
    func successReturnsValue() async throws {
        let result = try await withThrowingTimeout(.seconds(1)) {
            return 42
        }
        #expect(result == 42)
    }

    @Test("withThrowingTimeout throws FlowTestError.timeout on timeout")
    func timeoutThrows() async {
        do {
            _ = try await withThrowingTimeout(.milliseconds(50)) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 0
            }
            Issue.record("expected timeout error")
        } catch FlowTestError.timeout {
            // expected
        } catch {
            Issue.record("expected FlowTestError.timeout, got \(error)")
        }
    }

    @Test("withThrowingTimeout propagates body errors")
    func propagatesBodyErrors() async {
        struct TestError: Error, Equatable {}
        do {
            _ = try await withThrowingTimeout(.seconds(1)) {
                throw TestError()
            }
            Issue.record("expected TestError")
        } catch is TestError {
            // expected
        } catch {
            Issue.record("expected TestError, got \(error)")
        }
    }
}
