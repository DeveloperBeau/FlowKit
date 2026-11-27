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
        // One slot, and a new fix evicts the old one. A slow collector always
        // sees the newest location and never builds up a backlog.
        Flow.callbackFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            let manager = await managerFactory()
            let delegate = LocationDelegate(onLocation: { location in
                // trySend never suspends. It returns .enqueued when the value
                // is buffered, .dropped when a dropLatest buffer is full, and
                // .closed after the flow has ended.
                scope.trySend(location)
            })
            manager.delegate = delegate
            manager.startUpdatingLocation()

            await scope.awaitClose {
                manager.stopUpdatingLocation()
                manager.delegate = nil
                withExtendedLifetime(delegate) {}
            }
        }
    }
}
