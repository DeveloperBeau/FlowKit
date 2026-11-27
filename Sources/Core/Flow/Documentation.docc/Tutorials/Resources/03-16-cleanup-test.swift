import CoreLocation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds LocationTracker.
@testable import MyApp

@Suite("LocationTracker")
struct LocationTrackerTests {

    @Test("emits simulated location", .timeLimit(.minutes(1)))
    func emitsSimulatedLocation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })
        let expected = CLLocation(latitude: 37.3318, longitude: -122.0312)

        try await tracker.locations.asFlow().probing { reader in
            await mock.waitUntilStarted()
            mock.simulateLocation(expected)
            let received = try await reader.awaitValue()
            #expect(received.coordinate.latitude == expected.coordinate.latitude)
            #expect(received.coordinate.longitude == expected.coordinate.longitude)
        }
    }

    @Test("stops the manager when the collector goes away", .timeLimit(.minutes(1)))
    func stopsOnCancellation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })

        try await tracker.locations.asFlow().probing { _ in
            // Emit nothing. Wait until the manager runs, then let the
            // probing closure return, which cancels the collection.
            await mock.waitUntilStarted()
        }

        // Cancellation resumes awaitClose, and its closure stops the manager.
        await mock.waitUntilStopped()
        #expect(mock.stopCalled)
    }
}
