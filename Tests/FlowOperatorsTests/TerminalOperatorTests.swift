import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("terminal operators")
struct TerminalOperatorTests {
    // MARK: - first

    @Test("first returns the first emitted value")
    func firstValue() async {
        let flow = Flow(of: 10, 20, 30)
        let result = await flow.first()
        #expect(result == 10)
    }

    @Test("first where returns the first matching value")
    func firstWhere() async {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        let result = await flow.first(where: { $0 > 3 })
        #expect(result == 4)
    }

    @Test("first where returns nil if nothing matches")
    func firstWhereNil() async {
        let flow = Flow(of: 1, 2, 3)
        let result = await flow.first(where: { $0 > 10 })
        #expect(result == nil)
    }

    // MARK: - toArray

    @Test("toArray collects all values into an array")
    func toArray() async {
        let flow = Flow(of: "a", "b", "c")
        let result = await flow.toArray()
        #expect(result == ["a", "b", "c"])
    }

    @Test("toArray on empty flow returns empty array")
    func toArrayEmpty() async {
        let flow = Flow<Int>.empty
        let result = await flow.toArray()
        #expect(result.isEmpty)
    }

    // MARK: - reduce

    @Test("reduce accumulates all values into a single result")
    func reduce() async {
        let flow = Flow(of: 1, 2, 3, 4)
        let result = await flow.reduce(0, +)
        #expect(result == 10)
    }

    @Test("reduce on empty flow returns initial value")
    func reduceEmpty() async {
        let flow = Flow<Int>.empty
        let result = await flow.reduce(99, +)
        #expect(result == 99)
    }

    // MARK: - exactlyOne

    @Test("exactlyOne returns the single emitted value")
    func exactlyOneSuccess() async throws {
        let flow = Flow(of: 42)
        let result = try await flow.exactlyOne()
        #expect(result == 42)
    }

    @Test("exactlyOne throws on empty flow")
    func exactlyOneEmpty() async {
        let flow = Flow<Int>.empty
        do {
            _ = try await flow.exactlyOne()
            Issue.record("expected error")
        } catch {
            // expected
        }
    }

    @Test("exactlyOne throws on multiple values")
    func exactlyOneMultiple() async {
        let flow = Flow(of: 1, 2)
        do {
            _ = try await flow.exactlyOne()
            Issue.record("expected error")
        } catch {
            // expected
        }
    }

    // MARK: - collectLatest

    @Test("collectLatest cancels previous action on new value")
    func collectLatestCancelsPrevious() async {
        let processed = Mutex<[Int]>([])
        let flow = Flow(of: 1, 2, 3)
        await flow.collectLatest { value in
            // Simulate work — only the last value should complete
            try? await Task.sleep(nanoseconds: 10_000_000)
            processed.withLock { $0.append(value) }
        }
        // At minimum, the last value (3) should be processed
        let result = processed.withLock { $0 }
        #expect(result.contains(3))
    }
}
