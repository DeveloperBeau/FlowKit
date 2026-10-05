package import FlowCore
package import FlowTesting
@testable import FlowTestingCore

/// Reads several flows at once through ``FlowReader``s, with no deadline.
///
/// The clock-free counterpart of `TestScope`: each flow registered with
/// `probe(_:)` is collected until the scope's closure exits, and every read
/// suspends on the flow's own emissions.
package struct ProbeScope: Sendable {
    private let scope: FlowScope

    package static func run(
        _ block: @Sendable (ProbeScope) async throws -> Void
    ) async throws {
        let flowScope = FlowScope()
        defer { flowScope.cancel() }
        try await block(ProbeScope(scope: flowScope))
    }

    package func probe<Element: Sendable>(_ flow: Flow<Element>) -> FlowReader<Element> {
        let reader = FlowReader<Element>()
        scope.launch {
            await flow.collect { await reader.record(.value($0)) }
            await reader.record(.completed)
        }
        return reader
    }

    package func probe<Element: Sendable>(_ flow: ThrowingFlow<Element>) -> FlowReader<Element> {
        let reader = FlowReader<Element>()
        scope.launch {
            do {
                try await flow.collect { await reader.record(.value($0)) }
                await reader.record(.completed)
            } catch {
                await reader.record(.failed(error))
            }
        }
        return reader
    }
}
