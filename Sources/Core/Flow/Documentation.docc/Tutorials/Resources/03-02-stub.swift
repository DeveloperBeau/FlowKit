import CoreLocation
import Flow

actor LocationTracker {
    // Creates the manager. It runs on the main actor because CLLocationManager
    // delivers delegate callbacks on the run loop of the thread that made it.
    private let managerFactory: @MainActor @Sendable () -> any LocationManaging

    init(managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    /// A cold flow of GPS locations. Every collector runs its own producer block.
    nonisolated func locationUpdates() -> Flow<CLLocation> {
        Self.makeUpdates(managerFactory: managerFactory)
    }

    private static func makeUpdates(
        managerFactory: @MainActor @Sendable @escaping () -> any LocationManaging
    ) -> Flow<CLLocation> {
        Flow.callbackFlow { scope in
            // The block receives a ProducerScope. Registration comes next.
            scope.close()
        }
    }
}
