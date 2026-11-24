# Hot flows

A hot flow runs one shared execution and delivers each value to the collectors attached at the time. Cold `Flow` and `ThrowingFlow` do not do this. Convert a cold flow with `asStateFlow` or `asSharedFlow`, or create a `MutableStateFlow` or `MutableSharedFlow` directly.

[Hot vs cold streams](https://developerbeau.github.io/FlowKit/documentation/flow/hotvscoldstreams) is the catalogue article. This page is the layout of the types.

Hot flows do not complete. `toArray()`, `last()`, and a `collect` to the end stay suspended. Stop a collector by cancelling its task, or by an operator that has its answer (`first()`, `prefix(_:)`).

## StateFlow

`StateFlow` is a read-only protocol. It has a synchronous `value` and `asFlow()`. `Element` is `Sendable` and `Equatable`.

`MutableStateFlow` stores that value. `init` takes the initial value. Reading and writing `value` is synchronous and ordered by a `Mutex`. Setting a value equal to the current one does nothing, so collectors do not see it. `update`, `getAndUpdate`, `updateAndGet`, and `compareAndSet` are the read-modify-write operations. A transform may run more than once if writers race, and it runs outside the lock.

A single pipeline task delivers updates in the order they were applied. `asFlow()` registers a subscriber, emits the current value, then emits later distinct updates. `MutableStateFlow.asStateFlow()` returns a read-only `StateFlow` view. That is a different method from `Flow.asStateFlow(initialValue:strategy:clock:)`, which shares a cold upstream.

`waitForSubscribers(_:)` and `waitForSubscribers(atMost:)` suspend until the collector count crosses the bound. They are not requirements of the `StateFlow` protocol. A cancelled wait throws `CancellationError`.

`subscribed()` registers a subscriber before it returns. The flow it returns emits the value that was current at that call, then every later distinct update. [Registered subscriptions](#registered-subscriptions) has the rules.

## SharedFlow

`SharedFlow` exposes `subscriptionCount` and `asFlow()`. `MutableSharedFlow` is an actor. `init` takes `replay` (default 0), `extraBufferCapacity` (default 0), and `onBufferOverflow` (default `.suspend`).

`emit` sends to the collectors attached now. With `replay: 0`, a value emitted before a collector attaches is gone. A new collector then receives the replay buffer, then later values. `resetReplayCache()` clears that buffer. `MutableSharedFlow.asSharedFlow()` is the read-only view.

`.suspend` does not backpressure this type. The per-subscriber buffer is unbounded for `.suspend` and for a capacity of zero, because the `AsyncStream` continuation cannot suspend the emitter. `.dropOldest` and `.dropLatest` bound each subscriber to `replay + extraBufferCapacity`. `BufferOverflow` in `FlowSharedModels` describes the three policies. The channel path in [Cold flows](ColdFlows.md) is where `.suspend` really suspends, and only on `send`.

The same subscriber waiters as `MutableStateFlow` live here, and they are not part of the `SharedFlow` protocol.

## Registered subscriptions

`asFlow()` is cold. It registers its subscriber when a task starts to collect it, so a value emitted between `Task { }` and the first run of that task is lost with `replay: 0`. `subscribed()` on `MutableSharedFlow` and on `MutableStateFlow` registers the subscriber before it returns. It is synchronous and callable from any isolation. It is not a requirement of the `SharedFlow` or `StateFlow` protocol.

```swift
let incoming = events.subscribed()      // registered here
let consumer = Task {
    await incoming.collect { handle($0) }
}
connection.start()                      // nothing is missed
```

The returned flow delivers every value emitted after the call returns. Values wait in the subscriber's own buffer until a task collects the flow. That buffer follows the same overflow policy and capacity as an `asFlow()` subscriber, so the default policy keeps every value and a drop policy bounds an uncollected subscription. A `MutableSharedFlow` with a replay delivers the replay cache first. A `MutableStateFlow` delivers the value that was current at registration first.

The subscriber counts in `subscriptionCount` and resumes the subscriber waiters from the moment of the call. It is removed when the collecting task is cancelled, and when the returned flow is released without a collection.

The returned flow can be collected once. A second collection completes at once and emits nothing. If the hot flow is released first, the collection emits the buffered values and then completes.

`MulticastSubscription` keeps these subscribers in a registry behind a `Mutex`, beside the actor-isolated subscribers of `asFlow()`. `deliver` yields to both. A registration that waits for its replay is skipped by `deliver` until `MutableSharedFlow` has yielded the replay cache to it. That happens at the start of the next `emit`, or when the collection starts, so the replay always comes before later values and no value arrives twice.

## Sharing a cold upstream

`Flow.asStateFlow(initialValue:strategy:clock:)` and `Flow.asSharedFlow(replay:strategy:clock:)` collect the cold upstream once and fan the values out. The default strategy is `.whileSubscribed()`, which is a stop timeout of zero and a replay expiration of zero. `clock` defaults to `ContinuousClock()` and is any `Clock` whose duration is `Duration`, so a test passes a `TestClock`.

`SharingStrategy` has three cases:

- `.eager` starts the upstream when the hot flow is activated and leaves it running.
- `.lazy` starts on the first subscriber and leaves it running after the last one leaves.
- `.whileSubscribed(stopTimeout:replayExpiration:)` starts on the first subscriber. After the last subscriber leaves it waits `stopTimeout` before stopping the upstream, and clears a shared replay `replayExpiration` later. A subscriber that arrives in time cancels both waits. With the default `.zero`, the replay is cleared before the leaving collection returns.

`replayExpiration` applies to `asSharedFlow` only. `asStateFlow` keeps its value.

`SharingCoordinator` owns those decisions. The `asSharedFlow` path keeps tasks that were cancelled while an `emit` might still be in flight, and the replay reset awaits them before `resetReplayCache()`. An upstream that ignores cancellation holds the reset, and the next subscriber, until it returns. `asStateFlow` does not reset a replay. It cancels the upstream task on stop.

Both conversions return a small private wrapper (`CoordinatedStateFlow`, `CoordinatedSharedFlow`) that forwards to the mutable flow and tells the coordinator when subscribers appear and disappear.
