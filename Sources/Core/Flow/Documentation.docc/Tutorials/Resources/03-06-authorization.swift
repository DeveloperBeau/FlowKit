import CoreLocation
import Flow

private final class DelegateBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let collector: Collector<CLLocation>
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(collector: Collector<CLLocation>) {
        self.collector = collector
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func stop(manager: any LocationManaging) {
        manager.stopUpdatingLocation()
        manager.delegate = nil
        let cont = lock.withLock { continuation.take() }
        cont?.resume()
    }

    // MARK: - Authorization

    /// Returns `true` when the app has sufficient location permission.
    private var isAuthorized: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    // MARK: - Delegate callbacks

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Skip locations that arrive before the user grants permission.
        guard isAuthorized, let latest = locations.last else { return }
        Task { await collector.emit(latest) }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        let cont = lock.withLock { continuation.take() }
        cont?.resume()
    }
}

private extension Optional {
    mutating func take() -> Wrapped? {
        let value = self
        self = nil
        return value
    }
}
