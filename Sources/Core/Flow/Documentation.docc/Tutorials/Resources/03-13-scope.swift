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
        // Cancels every task launched on the scope. When this was the last
        // subscriber, the shared flow cancels the callbackFlow block. Its
        // awaitClose closure then stops the manager and clears the delegate.
        scope.cancel()
    }

    private func startObservingLocation() {
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
