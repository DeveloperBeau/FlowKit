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
            mock.simulateLocation(expected)
            let received = try await tester.awaitValue()
            #expect(received.coordinate.latitude == expected.coordinate.latitude)
            #expect(received.coordinate.longitude == expected.coordinate.longitude)
        }
        // .test exits → the collection task is cancelled → withTaskCancellationHandler
        // fires → stop(manager:) is called → stopUpdatingLocation() is invoked.
    }

    @Test("stops location manager on cancellation")
    func stopsOnCancellation() async throws {
        let mock = MockLocationManager()
        let tracker = LocationTracker(managerFactory: { mock })

        try await tracker.locationFlow.test { tester in
            // Don't emit any values. Just let the .test closure return,
            // which cancels the collection task.
            await tester.cancelAndIgnoreRemaining()
        }

        // The cancellation handler in the bridge must have fired.
        #expect(mock.stopCalled == true)
    }
}
