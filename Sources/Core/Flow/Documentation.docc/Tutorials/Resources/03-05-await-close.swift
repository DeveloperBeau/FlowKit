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
        Flow.callbackFlow { scope in
            let manager = await managerFactory()
            let delegate = LocationDelegate(onLocation: { scope.trySend($0) })
            manager.delegate = delegate
            manager.startUpdatingLocation()

            // Park here until the flow closes. The closure runs one time, on
            // every way out: cancellation, a finished collection, or close().
            await scope.awaitClose {
                manager.stopUpdatingLocation()
                manager.delegate = nil
                // The manager holds its delegate weakly. This keeps `delegate`
                // alive for as long as the block is parked.
                withExtendedLifetime(delegate) {}
            }
        }
    }
}
