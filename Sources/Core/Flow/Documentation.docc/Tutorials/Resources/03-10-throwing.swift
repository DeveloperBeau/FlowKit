import CoreLocation
import Flow

actor LocationTracker {
    private let managerFactory: @MainActor @Sendable () -> any LocationManaging

    init(managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    /// A cold flow that fails with the delegate's error, or with
    /// `LocationError.notAuthorized` when the user denies permission.
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
                // The collector receives the fixes sent before this call,
                // then its collect throws the error.
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
