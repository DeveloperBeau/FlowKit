import CoreLocation
import Flow

actor LocationTracker {
    // Factory that creates the underlying CLLocationManager.
    // Defaults to the real hardware; replaced with a mock in tests.
    private let managerFactory: @Sendable () -> any LocationManaging

    init(managerFactory: @Sendable @escaping () -> any LocationManaging = { CLLocationManager() }) {
        self.managerFactory = managerFactory
    }

    /// A cold `Flow` that emits authorized GPS locations.
    var locationFlow: Flow<CLLocation> {
        Flow { collector in
            // Implementation coming in the next steps.
        }
    }
}
