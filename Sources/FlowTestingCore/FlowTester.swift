import Foundation
public import Testing
import FlowSharedModels
import FlowCore

/// Records values emitted by a `Flow` under test and provides assertion methods.
public actor FlowTester<Element: Sendable> {
    private let base: FlowTesterBase<Element>

    public init() {
        self.base = FlowTesterBase<Element>()
    }

    public func recordValue(_ value: Element) async {
        await base.recordValue(value)
    }

    public func recordCompletion() async {
        await base.recordCompletion()
    }

    public func awaitValue(
        within timeout: Duration = .seconds(1),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Element {
        let event = try await base.awaitNextEvent(within: timeout)
        switch event {
        case .value(let v):
            return v
        case .completion:
            Issue.record("expected value but flow completed", sourceLocation: sourceLocation)
            throw FlowTestError.unexpectedCompletion
        case .failure(let error):
            Issue.record("expected value but flow failed with \(error)", sourceLocation: sourceLocation)
            throw FlowTestError.unexpectedCompletion
        }
    }

    public func expectValue(
        _ expected: Element,
        within timeout: Duration = .seconds(1),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws where Element: Equatable {
        let actual = try await awaitValue(within: timeout, sourceLocation: sourceLocation)
        #expect(actual == expected, sourceLocation: sourceLocation)
    }

    public func expectNoValue(
        within duration: Duration,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            let value = try await awaitValue(within: duration)
            Issue.record(
                "expected no value within \(duration) but received \(value)",
                sourceLocation: sourceLocation
            )
        } catch FlowTestError.timeout {
            // expected
        } catch {
            // other errors already recorded
        }
    }

    public func expectCompletion(
        within timeout: Duration = .seconds(1),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let event = try await base.awaitNextEvent(within: timeout)
        switch event {
        case .completion:
            return
        case .value(let v):
            Issue.record("expected completion but received value \(v)", sourceLocation: sourceLocation)
            throw FlowTestError.unexpectedValue
        case .failure(let error):
            Issue.record("expected completion but flow failed with \(error)", sourceLocation: sourceLocation)
            throw FlowTestError.unexpectedValue
        }
    }

    public func receivedValues() async -> [Element] {
        await base.snapshotValues()
    }

    public func cancelAndIgnoreRemaining() async {
        _ = await base.drainUnawaited()
    }

    internal func drainUnawaited() async -> [FlowTesterBase<Element>.Event] {
        await base.drainUnawaited()
    }
}
