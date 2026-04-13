import Testing
import Foundation
import FlowCore
@testable import FlowTestingCore

struct TestNetworkError: Error, Equatable {
    let code: Int
}

@Suite("ThrowingFlowTester")
struct ThrowingFlowTesterTests {
    @Test("awaitValue returns emitted value on throwing tester")
    func awaitValueReturnsValue() async throws {
        let tester = ThrowingFlowTester<String>()
        Task {
            await tester.recordValue("hello")
        }
        let value = try await tester.awaitValue(within: .seconds(1))
        #expect(value == "hello")
    }

    @Test("expectError with Equatable error passes on match")
    func expectEquatableErrorPasses() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task {
            await tester.recordError(TestNetworkError(code: 503))
        }
        try await tester.expectError(TestNetworkError(code: 503), within: .seconds(1))
    }

    @Test("expectError with predicate passes on match")
    func expectPredicateErrorPasses() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task {
            await tester.recordError(TestNetworkError(code: 503))
        }
        try await tester.expectError("5xx server error", within: .seconds(1)) { error in
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
        try await tester.expectCompletion(within: .seconds(1))
    }

    @Test("expectValue matches via ThrowingFlowTester")
    func expectValueMatches() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(42) }
        try await tester.expectValue(42, within: .seconds(1))
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
        await withKnownIssue {
            do {
                _ = try await tester.awaitValue(within: .seconds(1))
            } catch {}
        }
    }

    @Test("awaitValue throws when flow errors")
    func awaitValueOnError() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 500)) }
        await withKnownIssue {
            do {
                _ = try await tester.awaitValue(within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectCompletion throws when value arrives instead")
    func expectCompletionGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(42) }
        await withKnownIssue {
            do {
                try await tester.expectCompletion(within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectCompletion throws when error arrives instead")
    func expectCompletionGetsError() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 404)) }
        await withKnownIssue {
            do {
                try await tester.expectCompletion(within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectError records issue when value arrives instead")
    func expectErrorGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(1) }
        await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectError records issue when flow completes normally")
    func expectErrorGetsCompletion() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectError with wrong error type records issue")
    func expectErrorTypeMismatch() async throws {
        struct OtherError: Error, Equatable {}
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(OtherError()) }
        await withKnownIssue {
            do {
                try await tester.expectError(TestNetworkError(code: 500), within: .seconds(1))
            } catch {}
        }
    }

    @Test("expectError predicate records issue when value arrives")
    func predicateErrorGetsValue() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordValue(1) }
        await withKnownIssue {
            do {
                try await tester.expectError("any error", within: .seconds(1)) { _ in true }
            } catch {}
        }
    }

    @Test("expectError predicate records issue when completion arrives")
    func predicateErrorGetsCompletion() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordCompletion() }
        await withKnownIssue {
            do {
                try await tester.expectError("any error", within: .seconds(1)) { _ in true }
            } catch {}
        }
    }

    @Test("expectError predicate records issue when predicate returns false")
    func predicateErrorNoMatch() async throws {
        let tester = ThrowingFlowTester<Int>()
        Task { await tester.recordError(TestNetworkError(code: 500)) }
        await withKnownIssue {
            do {
                try await tester.expectError("code 404", within: .seconds(1)) { error in
                    (error as? TestNetworkError)?.code == 404
                }
            } catch {}
        }
    }

    @Test("expectNoValue records issue when value arrives")
    func expectNoValueGetsValue() async {
        let tester = ThrowingFlowTester<Int>()
        await tester.recordValue(1)
        await withKnownIssue {
            await tester.expectNoValue(within: .seconds(1))
        }
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
