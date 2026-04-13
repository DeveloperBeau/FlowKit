extension Flow {
    /// Launches collection of this flow in the given scope. The collection
    /// runs as a task owned by `scope`, which means cancelling the scope
    /// cancels the collection. Returns the launched task handle, which can
    /// be ignored for fire-and-forget launches.
    ///
    /// The flow is collected with a no-op sink — any side effects should be
    /// attached upstream using `onEach`:
    ///
    /// ```swift
    /// viewModel.navigationEvents.asFlow()
    ///     .onEach { [weak self] event in self?.handle(event) }
    ///     .launch(in: viewController.scope)
    /// ```
    @discardableResult
    public func launch(in scope: FlowScope) -> Task<Void, Never> {
        scope.launch {
            await self.collect { _ in }
        }
    }
}

extension ThrowingFlow {
    /// Launches collection of this throwing flow in the given scope. Errors
    /// thrown by the flow are silently swallowed — if you care about errors,
    /// handle them upstream with `.catch { }` before calling `launch(in:)`.
    @discardableResult
    public func launch(in scope: FlowScope) -> Task<Void, Never> {
        scope.launch {
            do {
                try await self.collect { _ in }
            } catch {
                // Swallowed by contract. Use .catch { } upstream to handle.
            }
        }
    }
}
