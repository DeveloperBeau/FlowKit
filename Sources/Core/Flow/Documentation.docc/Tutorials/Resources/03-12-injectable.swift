import CoreLocation
import Flow

actor LocationTracker {
    /// Shared, multicast location stream. One CLLocationManager (or mock) is
    /// activated when the first subscriber attaches and shut down when the
    /// last one disappears.
    nonisolated let locations: any SharedFlow<CLLocation>

    /// Production initializer: uses the real hardware.
    init() {
        self.locations = Self.makeColdLocationFlow(managerFactory: { CLLocationManager() })
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))
    }

    /// Test initializer: accepts any factory so tests can inject a mock.
    init(managerFactory: @Sendable @escaping () -> any LocationManaging) {
        self.locations = Self.makeColdLocationFlow(managerFactory: managerFactory)
            .asSharedFlow(replay: 1, strategy: .whileSubscribed(stopTimeout: .zero))
    }

    private static func makeColdLocationFlow(
        managerFactory: @Sendable @escaping () -> any LocationManaging
    ) -> Flow<CLLocation> {
        Flow { collector in
            let manager = managerFactory()      // ← replaced by mock in tests
            let bridge = DelegateBridge(collector: collector)
            manager.delegate = bridge

            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()

            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    bridge.setContinuation(continuation)
                }
            } onCancel: {
                bridge.stop(manager: manager)
            }
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

    private func isAuthorized(_ manager: CLLocationManager) -> Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard isAuthorized(manager), let latest = locations.last else { return }
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
