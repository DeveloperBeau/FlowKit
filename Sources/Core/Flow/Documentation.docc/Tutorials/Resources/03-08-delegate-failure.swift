import CoreLocation

enum LocationError: Error {
    case notAuthorized
}

/// Forwards `CLLocationManagerDelegate` callbacks to closures. It drops
/// updates that arrive before the user grants permission, and it reports
/// failures and a denied permission to `onFailure`.
final class LocationDelegate: NSObject, CLLocationManagerDelegate, Sendable {
    private let source: any LocationManaging
    private let onLocation: @Sendable (CLLocation) -> Void
    private let onFailure: @Sendable (any Error) -> Void

    init(
        manager: any LocationManaging,
        onLocation: @escaping @Sendable (CLLocation) -> Void,
        onFailure: @escaping @Sendable (any Error) -> Void
    ) {
        self.source = manager
        self.onLocation = onLocation
        self.onFailure = onFailure
    }

    private var isAuthorized: Bool {
        switch source.authorizationStatus {
        case .authorizedAlways:
            true
        #if !os(macOS)
        case .authorizedWhenInUse:
            true
        #endif
        default:
            false
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard isAuthorized, let latest = locations.last else { return }
        onLocation(latest)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        // "Location unknown" is transient. The manager keeps trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        onFailure(error)
    }

    /// Called after the user answers the permission prompt, and whenever the
    /// status changes while the app runs.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch source.authorizationStatus {
        case .denied, .restricted:
            onFailure(LocationError.notAuthorized)
        default:
            break
        }
    }
}
