package import FlowTesting
package import Testing

extension FlowReader {
    /// Asserts the flow fails with an error equal to `expected`.
    package func expectError<E: Error & Equatable>(
        _ expected: E,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await expectError(String(describing: expected), sourceLocation: sourceLocation) {
            ($0 as? E) == expected
        }
    }
}
