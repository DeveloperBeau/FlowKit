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

        try await tracker.locations.asFlow().probing { reader in
            mock.simulateLocation(expected)
            let received = try await reader.awaitValue()
            #expect(received.coordinate.latitude == expected.coordinate.latitude)
            #expect(received.coordinate.longitude == expected.coordinate.longitude)
        }
        // probing exits → the collection task is cancelled → withTaskCancellationHandler
        // fires → stop(manager:) is called → stopUpdatingLocation() is invoked.
    }

    @Test("stops location manager on cancellation")
    func stopsOnCancellation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })

        try await tracker.locations.asFlow().probing { reader in
            // Don't emit any values. Just let the probing closure return,
            // which cancels the collection task.
            await reader.cancelAndIgnoreRemaining()
        }

        // The cancellation handler in the bridge must have fired.
        #expect(mock.stopCalled == true)
    }
}
