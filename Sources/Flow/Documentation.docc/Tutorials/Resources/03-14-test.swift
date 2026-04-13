import CoreLocation
import Testing
import Flow
import FlowTesting

@Suite("LocationTracker")
struct LocationTrackerTests {

    @Test("emits simulated location")
    func emitsSimulatedLocation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })
        let expected = CLLocation(latitude: 37.3318, longitude: -122.0312)

        try await tracker.locationFlow.test { tester in
            // Simulate the hardware delivering a GPS fix.
            mock.simulateLocation(expected)

            let received = try await tester.awaitValue()
            #expect(received.coordinate.latitude == expected.coordinate.latitude)
            #expect(received.coordinate.longitude == expected.coordinate.longitude)
        }
    }
}
