import CoreLocation
import Flow

// MARK: - LocationTracker

actor LocationTracker {
    private let managerFactory: @Sendable () -> any LocationManaging

    init(managerFactory: @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    /// A cold `Flow` of authorized GPS locations.
    ///
    /// - The flow starts the hardware on first collection.
    /// - Locations emitted before authorization is granted are silently dropped.
    /// - The hardware stops automatically when the collecting task is cancelled.
    var locationFlow: Flow<CLLocation> {
        Flow { [managerFactory] collector in
            let manager = managerFactory()
            let bridge = DelegateBridge(collector: collector)
            manager.delegate = bridge

            // Request permission — the system shows the prompt once; subsequent
            // calls are no-ops if permission was already granted or denied.
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()

            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    bridge.setContinuation(continuation)
                }
            } onCancel: {
                bridge.stop(manager: manager)
            }

            // Reached when the continuation is resumed (cancellation, error, or
            // authorization denied). Cleanup is already done inside stop/resume.
        }
    }
}

// MARK: - DelegateBridge

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

    private var isAuthorized: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            stop(manager: manager)
        default:
            break
        }
    }
}

private extension Optional {
    mutating func take() -> Wrapped? {
        let value = self
        self = nil
        return value
    }
}
