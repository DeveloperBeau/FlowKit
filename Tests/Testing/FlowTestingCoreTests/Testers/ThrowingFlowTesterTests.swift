import Testing
import Foundation
import FlowCore
import FlowSharedModels
@testable import FlowTestingCore

/// True when the issue's message contains `fragment`. Used as a
/// `withKnownIssue` matcher so an unrelated failure recorded inside the block
/// still fails the test instead of being silently absorbed as the known issue.
private func issueContains(_ issue: Issue, _ fragment: String) -> Bool {
    issue.comments.contains { $0.rawValue.contains(fragment) }
}

struct TestNetworkError: Error, Equatable {
    let code: Int
}

/// A window a passing read never waits out. Reads here resolve the moment the
/// event is recorded, so the window only has to outlast any stall.
private let successWindow = Duration.seconds(3600)

@Suite("ThrowingFlowTester")
struct ThrowingFlowTesterTests {
    @Test("awaitValue returns emitted value on throwing tester")
    func awaitValueReturnsValue() async throws {
        let tester = ThrowingFlowTester<String>()
        Task {
            await tester.recordValue("hello")
        }
        let value = try await tester.awaitValue(within: successWindow)
        #expect(value == "hello")
    }

    @Test("expectError with Equatable error passes on match")
    func expectEquatableErrorPasses() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task {
            await tester.recordError(TestNetworkError(code: 503))
        }
        try await tester.expectError(TestNetworkError(code: 503), within: successWindow)
    }

    @Test("expectError with predicate passes on match")
    func expectPredicateErrorPasses() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task {
            await tester.recordError(TestNetworkError(code: 503))
        }
        try await tester.expectError("5xx server error", within: successWindow) { error in
            (error as? TestNetworkError)?.code ?? 0 >= 500
        }
    }

    @Test("expectNoValue passes when no value arrives")
    func expectNoValuePasses() async {
        let tester = ThrowingFlowTester<Int>()
        await tester.expectNoValue(within: .milliseconds(50))
    }

    @Test("expectCompletion passes on normal completion")
    func expectCompletionPasses() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        try await tester.expectCompletion(within: successWindow)
    }

    @Test("expectValue matches via ThrowingFlowTester")
    func expectValueMatches() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(42) }
        try await tester.expectValue(42, within: successWindow)
    }

    @Test("receivedValues returns buffered values")
    func receivedValuesSnapshot() async {
        let tester = ThrowingFlowTester<Int>()
        await tester.recordValue(1)
        await tester.recordValue(2)
        let values = await tester.receivedValues()
        #expect(values == [1, 2])
    }

    @Test("awaitValue throws unexpectedCompletion when flow completes")
    func awaitValueOnCompletion() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                _ = try await tester.awaitValue(within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected value but flow completed") }
        #expect(thrown.withLock { $0 } == .unexpectedCompletion)
    }

    @Test("awaitValue throws when flow errors")
    func awaitValueOnError() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 500)) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                _ = try await tester.awaitValue(within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected value but flow failed with") }
        #expect(thrown.withLock { $0 } == .unexpectedCompletion)
    }

    @Test("expectCompletion throws when value arrives instead")
    func expectCompletionGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(42) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectCompletion(within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected completion but received value 42") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectCompletion throws when error arrives instead")
    func expectCompletionGetsError() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 404)) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectCompletion(within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected completion but flow failed with") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectError records issue when value arrives instead")
    func expectErrorGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(1) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "but received value 1") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectError records issue when flow completes normally")
    func expectErrorGetsCompletion() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "but flow completed normally") }
        #expect(thrown.withLock { $0 } == .unexpectedCompletion)
    }

    @Test("expectError with wrong error type records issue")
    func expectErrorTypeMismatch() async throws {
        struct OtherError: Error, Equatable {}
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(OtherError()) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: successWindow)
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected error of type") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectError predicate records issue when value arrives")
    func predicateErrorGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(1) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError("any error", within: successWindow) { _ in true }
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected error matching 'any error' but received value 1") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectError predicate records issue when completion arrives")
    func predicateErrorGetsCompletion() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError("any error", within: successWindow) { _ in true }
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected error matching 'any error' but flow completed normally") }
        #expect(thrown.withLock { $0 } == .unexpectedCompletion)
    }

    @Test("expectError predicate records issue when predicate returns false")
    func predicateErrorNoMatch() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 500)) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectError("code 404", within: successWindow) { error in
                    (error as? TestNetworkError)?.code == 404
                }
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected error matching 'code 404' but got") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectNoValue records issue when value arrives")
    func expectNoValueGetsValue() async {
        let tester = ThrowingFlowTester<Int>()
        await tester.recordValue(1)
        await withKnownIssue {
            await tester.expectNoValue(within: successWindow)
        } matching: { issueContains($0, "expected no value within") }
    }

    @Test("cancelAndIgnoreRemaining discards buffered events")
    func cancelAndIgnore() async {
        let tester = ThrowingFlowTester<Int>()
        await tester.recordValue(1)
        await tester.cancelAndIgnoreRemaining()
        let values = await tester.receivedValues()
        #expect(values.isEmpty)
    }
}
