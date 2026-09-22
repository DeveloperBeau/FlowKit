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
