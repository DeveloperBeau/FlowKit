import CoreLocation
// MyApp is the app target that holds LocationManaging.
@testable import MyApp

// MARK: - MockLocationManager

/// A test double for `LocationManaging`. Lets tests drive the delegate directly
/// without real GPS hardware.
final class MockLocationManager: LocationManaging, @unchecked Sendable {
    weak var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse

    private(set) var startCalled = false
    private(set) var stopCalled = false

    func requestWhenInUseAuthorization() {}

    private let startSignal = AsyncStream<Void>.makeStream()

    func startUpdatingLocation() {
        startCalled = true
        startSignal.continuation.yield()
    }

    /// Suspends until the tracker has started this manager. The tracker starts
    /// it when the first subscriber arrives, so a test waits here before it
    /// simulates a location.
    func waitUntilStarted() async {
        for await _ in startSignal.stream { return }
    }

    private let stopSignal = AsyncStream<Void>.makeStream()

    func stopUpdatingLocation() {
        stopCalled = true
        stopSignal.continuation.yield()
    }

    /// Suspends until the tracker has stopped this manager.
    func waitUntilStopped() async {
        for await _ in stopSignal.stream { return }
    }

    /// Calls `didUpdateLocations` on the stored delegate, simulating a GPS fix.
    func simulateLocation(_ location: CLLocation) {
        delegate?.locationManager?(
            StatusReportingManager(status: authorizationStatus),
            didUpdateLocations: [location]
        )
    }
}

/// A `CLLocationManager` that reports a fixed authorization status. The
/// bridge reads the status from the manager the delegate callback passes in.
private final class StatusReportingManager: CLLocationManager, @unchecked Sendable {
    private let status: CLAuthorizationStatus

    init(status: CLAuthorizationStatus) {
        self.status = status
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { status }
}
