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
        // The shared flow is multicast: every consumer shares one
        // CLLocationManager. The hardware starts on the first subscriber and
        // stops on the last unsubscribe.
        //
        // The one-slot buffer inside callbackFlow protects the producer side.
        // .keepingLatest() adds a one-element drop-oldest buffer for this
        // consumer, so a slow redraw skips superseded locations.
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
