import UIKit
import CoreLocation
import Flow

@MainActor
final class MapViewController: UIViewController {
    private let tracker = LocationTracker()
    private let scope = FlowScope()

    override func viewDidLoad() {
        super.viewDidLoad()
        startObservingLocation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Cancels all tasks launched on the scope.
        // This triggers withTaskCancellationHandler inside the bridge,
        // which calls stopUpdatingLocation() and clears the delegate.
        scope.cancel()
    }

    private func startObservingLocation() {
        // tracker.locations is multicast: all subscribers across the app share
        // a single CLLocationManager. The hardware starts on first subscriber
        // and stops on last, so opening this view never spawns a duplicate.
        let flow = tracker.locations.asFlow().keepingLatest()

        // launch(_:) starts a Task tied to this scope's lifetime.
        scope.launch {
            await flow.collect { [weak self] location in
                await self?.updateMap(with: location)
            }
        }
    }

    private func updateMap(with location: CLLocation) {
        // Update your map annotation, heading indicator, etc.
    }
}
