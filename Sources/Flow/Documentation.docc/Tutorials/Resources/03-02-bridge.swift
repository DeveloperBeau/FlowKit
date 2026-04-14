import CoreLocation
import Flow

actor LocationTracker {
    private let managerFactory: @Sendable () -> any LocationManaging

    init(managerFactory: @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    var locationFlow: Flow<CLLocation> {
        Flow { collector in
            // Bridge class wires CLLocationManager callbacks into the collector.
        }
    }
}

// MARK: - Delegate bridge

/// Forwards `CLLocationManagerDelegate` callbacks into a `Collector<CLLocation>`.
/// Instances of this class are created inside the flow body and are not
/// shared. Each collection gets its own independent bridge.
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
