import CoreLocation
import Flow

actor LocationTracker {
    private let managerFactory: @Sendable () -> any LocationManaging

    init(managerFactory: @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    var locationFlow: Flow<CLLocation> {
        Flow { [managerFactory] collector in
            let manager = managerFactory()
            let bridge = DelegateBridge(collector: collector)
            manager.delegate = bridge

            manager.startUpdatingLocation()

            // withTaskCancellationHandler fires synchronously when the surrounding
            // task is cancelled. The onCancel closure stops hardware and resumes
            // the continuation so the flow body can return cleanly.
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    bridge.setContinuation(continuation)
                }
            } onCancel: {
                bridge.stop(manager: manager)
            }

            manager.stopUpdatingLocation()
            manager.delegate = nil
        }
    }
}

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

    /// Called from the `onCancel` closure. Stops the manager and resumes the
    /// suspended continuation so the flow body can exit.
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
}

private extension Optional {
    mutating func take() -> Wrapped? {
        let value = self
        self = nil
        return value
    }
}
