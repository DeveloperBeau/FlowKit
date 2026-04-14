import CoreLocation
import Flow

actor LocationTracker {
    /// Injected factory. Returns `CLLocationManager()` in production,
    /// or a `MockLocationManager` in tests.
    private let managerFactory: @Sendable () -> any LocationManaging

    /// Production initializer: uses the real hardware.
    init() {
        self.managerFactory = { CLLocationManager() }
    }

    /// Test initializer: accepts any factory so tests can inject a mock.
    init(managerFactory: @Sendable @escaping () -> any LocationManaging) {
        self.managerFactory = managerFactory
    }

    var locationFlow: Flow<CLLocation> {
        Flow { [managerFactory] collector in
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
