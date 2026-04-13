import CoreLocation
import Testing
import Flow

// MARK: - MockLocationManager

/// A test double for `LocationManaging`. Lets tests drive the delegate directly
/// without real GPS hardware.
final class MockLocationManager: LocationManaging, @unchecked Sendable {
    weak var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse

    private(set) var startCalled = false
    private(set) var stopCalled = false

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        startCalled = true
    }

    func stopUpdatingLocation() {
        stopCalled = true
    }

    /// Calls `didUpdateLocations` on the stored delegate, simulating a GPS fix.
    func simulateLocation(_ location: CLLocation) {
        delegate?.locationManager?(
            CLLocationManager(),
            didUpdateLocations: [location]
        )
    }
}
