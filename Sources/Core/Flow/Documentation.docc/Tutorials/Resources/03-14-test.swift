import CoreLocation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds LocationTracker.
@testable import MyApp

@Suite("LocationTracker")
struct LocationTrackerTests {

    @Test("emits simulated location")
    func emitsSimulatedLocation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })
        let expected = CLLocation(latitude: 37.3318, longitude: -122.0312)

        try await tracker.locations.asFlow().probing { reader in
            // Wait for the tracker to start the manager, then simulate the
            // hardware delivering a GPS fix.
            await mock.waitUntilStarted()
            mock.simulateLocation(expected)

            let received = try await reader.awaitValue()
            #expect(received.coordinate.latitude == expected.coordinate.latitude)
            #expect(received.coordinate.longitude == expected.coordinate.longitude)
        }
    }
}
