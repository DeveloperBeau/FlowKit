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
        // .keepingLatest() adds a one-element drop-oldest buffer between the
        // GPS hardware and the view controller. When the hardware emits faster
        // than the UI can render, intermediate locations are discarded and only
        // the most recent update is processed.
        let flow = tracker.locationFlow.keepingLatest()

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
