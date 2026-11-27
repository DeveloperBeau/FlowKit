import CoreLocation
import Flow

/// Replays a recorded track, for a simulator build or a UI test.
///
/// A replay is not a delegate callback, so its producer can suspend. With
/// `.suspend` and a capacity of 8, `send(_:)` waits while eight locations are
/// unconsumed, and a slow collector slows the replay down instead of losing
/// fixes. The block returns when the track ends, and that completes the flow.
func replay(_ track: [CLLocation]) -> Flow<CLLocation> {
    Flow.channelFlow(bufferCapacity: 8, onBufferOverflow: .suspend) { scope in
        for location in track {
            // .closed means the collector went away. Stop producing.
            guard await scope.send(location) == .enqueued else { return }
        }
    }
}
