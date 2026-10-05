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

    /// Reads until a value equal to `target` arrives, discarding earlier ones.
    ///
    /// For a flow that may pass through intermediate values on the way to the
    /// one a test cares about. The flow ending first fails the read.
    package func awaitValue(
        equalTo target: Element,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws where Element: Equatable {
        while try await awaitValue(sourceLocation: sourceLocation) != target {}
    }
}
