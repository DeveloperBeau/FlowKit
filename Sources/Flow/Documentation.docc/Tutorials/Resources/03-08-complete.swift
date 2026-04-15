import CoreLocation
import Flow

// MARK: - LocationTracker

/// A multi-subscriber location source. The hardware spins up on the first
/// subscriber and stops the moment the last one disappears, so views, view
/// models, and analytics can all observe the same stream without spawning
/// duplicate `CLLocationManager` instances or leaking them.
actor LocationTracker {
    /// Shared location stream. Use this from every consumer.
    nonisolated let locations: any SharedFlow<CLLocation>

    init(managerFactory: @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.locations = Self.makeColdLocationFlow(managerFactory: managerFactory)
            .asSharedFlow(
                replay: 1,
                strategy: .whileSubscribed(stopTimeout: .zero)
            )
    }

    /// The underlying cold flow. One `CLLocationManager` is created per
    /// upstream activation, which `whileSubscribed` keeps to exactly one
    /// across all current subscribers.
    private static func makeColdLocationFlow(
        managerFactory: @Sendable @escaping () -> any LocationManaging
    ) -> Flow<CLLocation> {
        Flow { collector in
            let manager = managerFactory()
            let bridge = DelegateBridge(collector: collector)
            manager.delegate = bridge

            // Request permission. The system shows the prompt once; subsequent
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

            // Reached when the continuation is resumed by cancellation, error,
            // or authorization denial. The bridge has already cleaned up.
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
