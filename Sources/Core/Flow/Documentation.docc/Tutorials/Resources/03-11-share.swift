import CoreLocation
import Flow

/// A multi-subscriber location source. The hardware starts with the first
/// subscriber and stops when the last one leaves, so views, view models and
/// analytics can observe the same stream without extra `CLLocationManager`
/// instances.
actor LocationTracker {
    private let managerFactory: @MainActor @Sendable () -> any LocationManaging

    /// Shared location stream. Errors end it quietly. Use `locationUpdates()`
    /// when a caller needs to see the error.
    nonisolated let locations: any SharedFlow<CLLocation>

    init(managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
        self.locations = Self.makeUpdates(managerFactory: managerFactory)
            .catch { _, _ in }
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))
    }

    /// A cold flow with its own `CLLocationManager` for each collector.
    nonisolated func locationUpdates() -> ThrowingFlow<CLLocation> {
        Self.makeUpdates(managerFactory: managerFactory)
    }

    private static func makeUpdates(
        managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging
    ) -> ThrowingFlow<CLLocation> {
        ThrowingFlow.callbackFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            let manager = await managerFactory()
            let delegate = LocationDelegate(
                manager: manager,
                onLocation: { scope.trySend($0) },
                onFailure: { scope.close(throwing: $0) }
            )
            manager.delegate = delegate

            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()

            await scope.awaitClose {
                manager.stopUpdatingLocation()
                manager.delegate = nil
                withExtendedLifetime(delegate) {}
            }
        }
    }
}
