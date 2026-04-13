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

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { await collector.emit(latest) }
    }

    /// Hardware or permission errors end the flow immediately. Resuming the
    /// continuation lets the flow body return, which stops the manager via the
    /// cleanup code that runs after `withTaskCancellationHandler`.
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
