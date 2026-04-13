import CoreLocation
import Flow

/// Protocol abstracting the subset of `CLLocationManager` that `LocationTracker`
/// uses. Conforming `CLLocationManager` lets production code stay unchanged;
/// a `MockLocationManager` can be injected in tests.
protocol LocationManaging: AnyObject, Sendable {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

// Make CLLocationManager conform to the protocol.
extension CLLocationManager: LocationManaging {}
