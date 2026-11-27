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

            // Mistake: the block returns here. The flow completes at once,
            // and `delegate` is released while the manager keeps running.
        }
    }
}
