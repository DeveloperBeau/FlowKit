# Hot flows

A hot flow runs one shared execution and delivers each value to the collectors attached at the time. Cold `Flow` and `ThrowingFlow` do not do this. Convert a cold flow with `asStateFlow` or `asSharedFlow`, or create a `MutableStateFlow` or `MutableSharedFlow` directly.

[Hot vs cold streams](https://developerbeau.github.io/FlowKit/documentation/flow/hotvscoldstreams) is the catalogue article. This page is the layout of the types.

A hot flow does not complete by itself. `toArray()`, `last()`, and a `collect` to the end stay suspended while the flow is open. Stop one collector by cancelling its task, or by an operator that has its answer (`first()`, `prefix(_:)`). The owner of a `MutableStateFlow` or a `MutableSharedFlow` ends it for every collector with `close()`. See [Closing a hot flow](#closing-a-hot-flow).

## StateFlow

`StateFlow` is a read-only protocol. It has a synchronous `value` and `asFlow()`. `Element` is `Sendable` and `Equatable`.

`MutableStateFlow` stores that value. `init` takes the initial value. Reading and writing `value` is synchronous and ordered by a `Mutex`. Setting a value equal to the current one does nothing, so collectors do not see it. `update`, `getAndUpdate`, `updateAndGet`, and `compareAndSet` are the read-modify-write operations. A transform may run more than once if writers race, and it runs outside the lock.

A single pipeline task delivers updates in the order they were applied. `asFlow()` registers a subscriber, emits the current value, then emits later distinct updates. `MutableStateFlow.asStateFlow()` returns a read-only `StateFlow` view. That is a different method from `Flow.asStateFlow(initialValue:strategy:clock:)`, which shares a cold upstream.

`waitForSubscribers(_:)` and `waitForSubscribers(atMost:)` suspend until the collector count crosses the bound. They are not requirements of the `StateFlow` protocol. A cancelled wait throws `CancellationError`.

`subscribed()` registers a subscriber before it returns. The flow it returns emits the value that was current at that call, then every later distinct update. [Registered subscriptions](#registered-subscriptions) has the rules.

## SharedFlow

`SharedFlow` exposes `subscriptionCount` and `asFlow()`. `MutableSharedFlow` is an actor. `init` takes `replay` (default 0), `extraBufferCapacity` (default 0), and `onBufferOverflow` (default `.suspend`).

`emit` sends to the collectors attached now. With `replay: 0`, a value emitted before a collector attaches is gone. A new collector then receives the replay buffer, then later values. `resetReplayCache()` clears that buffer. `MutableSharedFlow.asSharedFlow()` is the read-only view.

`tryEmit(_:)` is the same publish with no `await`. It is `nonisolated`, so a delegate method, a notification block, or a C callback can call it from any thread. The subscriber list and the replay buffer each sit behind a `Mutex` and not behind the actor, and `emit` goes through the same path. `tryEmit` holds the replay lock across the fan-out. Calls that race each other then reach every subscriber and the replay buffer in one common order, and calls made in order from one thread keep that order. It returns `true` for every policy the flow has today, because no policy makes the flow refuse a value. Only a closed flow refuses, and `tryEmit` then returns `false`.

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

`MulticastSubscription` keeps these subscribers in a registry behind the same `Mutex` as the subscribers that `MutableStateFlow.asFlow()` adds on the actor. Synchronous code adds and removes a registration, and a delivery yields to both under that lock. `MutableSharedFlow.asFlow()` uses the registry too, when its collection starts. A value published while a new collector reads the replay then arrives after the replay, one time only. A registration that waits for its replay is skipped by a delivery until `MutableSharedFlow` has yielded the replay cache to it. That happens at the start of the next `emit` or `tryEmit`, or when the collection starts. Both hold the replay lock, so the replay always comes before later values and no value arrives twice.

## Closing a hot flow

`MutableStateFlow.close()` and `MutableSharedFlow.close()` end the flow. Each attached collector receives the values already sent to it, then its `collect` returns. A slow collector still drains its buffer first. Close is final. A second call does nothing, and there is no reopen.

After close, publishing does nothing. `MutableSharedFlow.emit` and `tryEmit` deliver no value and leave the replay cache as it was, and `tryEmit` returns `false`. On `MutableStateFlow`, a write to `value`, `send`, and `compareAndSet` with a different value leave the last value in place, and `compareAndSet` returns `false`. `update`, `getAndUpdate`, and `updateAndGet` return the last value and do not run the transform. `value` still reads the last value.

A collector that attaches after close returns without waiting. On a `MutableSharedFlow` it receives nothing, not even the replay. On a `MutableStateFlow` it receives the last value first.

Close ends a `subscribed()` flow the same way. A collection of it receives the values sent before the close, then returns, and so does a collection that starts after the close. `subscribed()` on a flow that is already closed registers nothing. On a `MutableSharedFlow` the returned flow completes at once with no values. On a `MutableStateFlow` it emits the last value, then completes.

`MutableStateFlow.close()` is synchronous. It ends the pipeline, and the pipeline task finishes the subscribers after the updates that were applied before the close. `MutableSharedFlow.close()` is isolated to the actor, so the caller awaits it. Both are safe to call at the same time as publishers and as other calls to `close()`. The closed flag of a `MutableSharedFlow` sits behind the same lock as the subscriber list. A `tryEmit` that races `close()` then reaches every attached collector and the replay cache, or none of them.

A closed flow has no subscribers. `subscriptionCount` is zero and `waitForSubscribers(atMost: 0)` returns. Do not wait for collectors on a closed flow. `waitForSubscribers(_:)` for one or more collectors can stay suspended until the caller is cancelled.

The read-only views from `MutableStateFlow.asStateFlow()` and `MutableSharedFlow.asSharedFlow()` forward to the mutable flow, so their collectors return too. The views do not expose `close()`. The flows from `Flow.asStateFlow(initialValue:strategy:clock:)` and `Flow.asSharedFlow(replay:strategy:clock:)` also have no `close()`. The sharing strategy owns their lifetime.

## Sharing a cold upstream

`Flow.asStateFlow(initialValue:strategy:clock:)` and `Flow.asSharedFlow(replay:strategy:clock:)` collect the cold upstream once and fan the values out. The default strategy is `.whileSubscribed()`, which is a stop timeout of zero and a replay expiration of zero. `clock` defaults to `ContinuousClock()` and is any `Clock` whose duration is `Duration`, so a test passes a `TestClock`.

`SharingStrategy` has three cases:

- `.eager` starts the upstream when the hot flow is activated and leaves it running.
- `.lazy` starts on the first subscriber and leaves it running after the last one leaves.
- `.whileSubscribed(stopTimeout:replayExpiration:)` starts on the first subscriber. After the last subscriber leaves it waits `stopTimeout` before stopping the upstream, and clears a shared replay `replayExpiration` later. A subscriber that arrives in time cancels both waits. With the default `.zero`, the replay is cleared before the leaving collection returns.

`replayExpiration` applies to `asSharedFlow` only. `asStateFlow` keeps its value.

`SharingCoordinator` owns those decisions. The `asSharedFlow` path keeps tasks that were cancelled while an `emit` might still be in flight, and the replay reset awaits them before `resetReplayCache()`. An upstream that ignores cancellation holds the reset, and the next subscriber, until it returns. `asStateFlow` does not reset a replay. It cancels the upstream task on stop.

Both conversions return a small private wrapper (`CoordinatedStateFlow`, `CoordinatedSharedFlow`) that forwards to the mutable flow and tells the coordinator when subscribers appear and disappear.
