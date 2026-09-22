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

@Suite("FlowTester")
struct FlowTesterTests {
    @Test("awaitValue returns the first emitted value")
    func awaitValueReturnsFirst() async throws {
        let tester = FlowTester<String>()
        Task {
            await tester.recordValue("hello")
        }
        let value = try await tester.awaitValue(within: .seconds(1))
        #expect(value == "hello")
    }

    @Test("expectValue matches the first emitted value")
    func expectValueMatches() async throws {
        let tester = FlowTester<Int>()
        Task {
            await tester.recordValue(42)
        }
        try await tester.expectValue(42, within: .seconds(1))
    }

    @Test("expectNoValue passes when no value arrives within window")
    func expectNoValuePasses() async {
        let tester = FlowTester<Int>()
        await tester.expectNoValue(within: .milliseconds(50))
    }

    @Test("expectCompletion passes on normal completion")
    func expectCompletionPasses() async throws {
        let tester = FlowTester<Int>()
        Task {
            await tester.recordCompletion()
        }
        try await tester.expectCompletion(within: .seconds(1))
    }

    @Test("receivedValues returns snapshot of buffered values")
    func receivedValuesSnapshot() async {
        let tester = FlowTester<Int>()
        await tester.recordValue(1)
        await tester.recordValue(2)
        await tester.recordValue(3)
        let values = await tester.receivedValues()
        #expect(values == [1, 2, 3])
    }

    @Test("cancelAndIgnoreRemaining discards buffered events")
    func cancelAndIgnore() async {
        let tester = FlowTester<Int>()
        await tester.recordValue(1)
        await tester.recordValue(2)
        await tester.cancelAndIgnoreRemaining()
        let values = await tester.receivedValues()
        #expect(values.isEmpty)
    }

    @Test("awaitValue throws unexpectedCompletion when flow completes")
    func awaitValueOnCompletion() async throws {
        let tester = FlowTester<Int>()
        Task { await tester.recordCompletion() }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                _ = try await tester.awaitValue(within: .seconds(1))
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected value but flow completed") }
        #expect(thrown.withLock { $0 } == .unexpectedCompletion)
    }

    @Test("expectCompletion throws unexpectedValue when value arrives")
    func expectCompletionGetsValue() async throws {
        let tester = FlowTester<Int>()
        Task { await tester.recordValue(99) }
        let thrown = Mutex<FlowTestError?>(nil)
        try await withKnownIssue {
            do {
                try await tester.expectCompletion(within: .seconds(1))
            } catch let error as FlowTestError {
                thrown.withLock { $0 = error }
            }
        } matching: { issueContains($0, "expected completion but received value 99") }
        #expect(thrown.withLock { $0 } == .unexpectedValue)
    }

    @Test("expectNoValue records issue when value arrives")
    func expectNoValueGetsValue() async {
        let tester = FlowTester<Int>()
        await tester.recordValue(1)
        await withKnownIssue {
            await tester.expectNoValue(within: .seconds(1))
        } matching: { issueContains($0, "expected no value within") }
    }
}
