import CoreLocation
// MyApp is the app target that holds LocationManaging.
@testable import MyApp

// MARK: - MockLocationManager

/// A test double for `LocationManaging`. Tests drive the delegate directly
/// and need no GPS hardware.
final class MockLocationManager: LocationManaging, @unchecked Sendable {
    weak var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    private(set) var stopCalled = false

    private let startSignal = AsyncStream<Void>.makeStream()
    private let stopSignal = AsyncStream<Void>.makeStream()

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        startSignal.continuation.yield()
    }

    func stopUpdatingLocation() {
        stopCalled = true
        stopSignal.continuation.yield()
    }

    /// Suspends until the tracker has started this manager. A test waits here
    /// before it simulates a location.
    func waitUntilStarted() async {
        for await _ in startSignal.stream { return }
    }

    /// Suspends until the tracker has stopped this manager.
    func waitUntilStopped() async {
        for await _ in stopSignal.stream { return }
    }

    /// Calls `didUpdateLocations` on the stored delegate, as a GPS fix would.
    func simulateLocation(_ location: CLLocation) {
        delegate?.locationManager?(CLLocationManager(), didUpdateLocations: [location])
    }

    /// Calls `didFailWithError` on the stored delegate.
    func simulateFailure(_ error: any Error) {
        delegate?.locationManager?(CLLocationManager(), didFailWithError: error)
    }
}
