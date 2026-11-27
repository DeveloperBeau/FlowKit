import CoreLocation
import Flow

actor LocationTracker {
    private let managerFactory: @MainActor @Sendable () -> any LocationManaging

    init(managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    nonisolated func locationUpdates() -> Flow<CLLocation> {
        Self.makeUpdates(managerFactory: managerFactory)
    }

    private static func makeUpdates(
        managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging
    ) -> Flow<CLLocation> {
        Flow.callbackFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            let manager = await managerFactory()
            let delegate = LocationDelegate(
                manager: manager,
                onLocation: { scope.trySend($0) },
                // A Flow cannot fail. close() ends it, and awaitClose then
                // stops the manager.
                onFailure: { _ in scope.close() }
            )
            manager.delegate = delegate

            // The system shows the prompt one time. Later calls do nothing.
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
