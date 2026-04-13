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

            // Suspend here indefinitely. The manager keeps emitting while this
            // continuation is suspended. We resume (and the flow ends) only when
            // the caller cancels the surrounding task.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Cancellation wiring added in the next step.
                _ = continuation   // placeholder — suspension never resumes here yet
            }

            manager.stopUpdatingLocation()
            manager.delegate = nil
        }
    }
}

private final class DelegateBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let collector: Collector<CLLocation>

    init(collector: Collector<CLLocation>) {
        self.collector = collector
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { await collector.emit(latest) }
    }
}
