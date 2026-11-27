import CoreLocation

/// Forwards `CLLocationManagerDelegate` callbacks to a closure. The delegate
/// knows nothing about `Flow`. The flow body decides what the closure does.
final class LocationDelegate: NSObject, CLLocationManagerDelegate, Sendable {
    private let onLocation: @Sendable (CLLocation) -> Void

    init(onLocation: @escaping @Sendable (CLLocation) -> Void) {
        self.onLocation = onLocation
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        onLocation(latest)
    }
}
