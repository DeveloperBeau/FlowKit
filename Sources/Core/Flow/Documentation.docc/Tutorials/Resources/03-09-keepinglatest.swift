import UIKit
import CoreLocation
import Flow

@MainActor
final class MapViewController: UIViewController {
    private let tracker = LocationTracker()

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservingLocation()
    }

    private func startObservingLocation() {
        // The shared flow is multicast: every consumer subscribes to the same
        // CLLocationManager. The hardware spins up on the first subscriber and
        // shuts down on the last unsubscribe, with no per-view-controller leaks.
        //
        // .keepingLatest() adds a one-element drop-oldest buffer between the
        // GPS hardware and the view controller. When the hardware emits faster
        // than the UI can render, intermediate locations are discarded and only
        // the most recent update is processed.
        let flow = tracker.locations.asFlow().keepingLatest()

        Task {
            await flow.collect { [weak self] location in
                await self?.updateMap(with: location)
            }
        }
    }

    private func updateMap(with location: CLLocation) {
        // Update your map annotation, heading indicator, etc.
    }
}
