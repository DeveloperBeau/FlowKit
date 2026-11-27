import CoreLocation

/// The part of `CLLocationManager` that `LocationTracker` uses. The real
/// manager conforms to it, and a test double conforms to it in the last section.
protocol LocationManaging: AnyObject, Sendable {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: LocationManaging {}
