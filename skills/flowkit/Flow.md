# Flow

`import Flow` gives the cold types, the operators, the hot types and `FlowScope`.

## Flow is not AsyncStream

| | `Flow` / `ThrowingFlow` | `AsyncStream` |
|---|---|---|
| Start | The body runs only when you call `collect`. | The producer runs when you make the stream. |
| Collectors | Each `collect` runs the body again, independently. | One consumer. |
| Replay | None. A new collector starts from the beginning. | None. |
| Multicast | On `Flow` only, after `asStateFlow` or `asSharedFlow`. A `ThrowingFlow` must `catch` first. | No. |
| Failure | `Flow` cannot fail. `ThrowingFlow` can. | `AsyncThrowingStream` for failure. |

- `collect` returns only when the body returns. A body that never returns makes `collect`
  suspend until the task is cancelled.
- `collector.emit(value)` calls the downstream action directly and suspends until it returns.
  Thus, with no `buffer`, a slow collector slows the producer.
- There is no scheduler hop. The body runs in the task that collects. There is no `flowOn`.
  `observe(on:)`, `receive(on:)` and `subscribeOn` are unavailable. Isolate the collecting side
  with an actor or `@MainActor`.
- The names of RxSwift and Combine are marked `unavailable` with a message that gives the FlowKit
  name. Examples: `distinctUntilChanged` is `removeDuplicates()`, `startWith` is `onStart`,
  `withLatestFrom` is `combineLatest`, `share(replay:)` is `asSharedFlow`, `sink` is `collect`,
  `store(in:)` and `disposed(by:)` are `launch(in:)` with a `FlowScope`, `tryMap` is
  `mapThrowing`, `PublishSubject` is `MutableSharedFlow`, `BehaviorSubject` and
  `CurrentValueSubject` are `MutableStateFlow`.
- `Flow` cannot fail. `mapThrowing` is the explicit bridge from a `Flow` to a `ThrowingFlow`.
  `catch` turns a `ThrowingFlow` back into a `Flow`. There is no `Flow.catch`.
- Bridge to `AsyncSequence`: `asAsyncStream()` is on `Flow` only. It collects in a new task,
  buffers without limit and cancels the collection when the consumer stops. `ThrowingFlow` uses
  `asAsyncThrowingStream()`, with the same unbounded buffer and the same cancel when the
  consumer stops. A `Sendable` `AsyncSequence` of `Sendable` values becomes a `ThrowingFlow`
  with `asThrowingFlow()`. `AsyncSequence.asFlow()` needs `Failure == Never`. It is available
  on iOS 18+, macOS 15+, tvOS 18+, watchOS 11+ and visionOS 2+.

## Operators

| Group | Operators |
|---|---|
| Transform | `map`, `mapThrowing`, `compactMap`, `filter`, `filterIsInstance`, `transform`, `scan`, `enumerated`, `chunks(ofCount:)` |
| Slice | `prefix(_:)`, `prefix(while:)`, `dropFirst(_:)`, `drop(while:)` |
| Rate | `debounce(for:clock:)`, `throttle`, `sample`, `removeDuplicates()`, `removeDuplicates(by:)` |
| Flatten | `flatMap`, `flatMap(maxConcurrent:)` (`Flow` only), `flatMapLatest`, `mapLatest`, `transformLatest` |
| Combine | `zip`, `combineLatest` (up to six flows), `Flow.merge(_:)` |
| Lifecycle | `onStart`, `onEach`, `onCompletion`, `onEmpty` |
| Errors | `catch`, `retry`, `retryWhen` (all `ThrowingFlow` only), `timeout(for:clock:)` |
| Buffer | `buffer(size:policy:)`, `bufferUnbounded()`, `keepingLatest()` (all `Flow` only) |
| Terminal | `collect`, `first`, `toArray`, `last`, `count`, `reduce`, `exactlyOne`, `collectLatest`, `contains(where:)`, `allSatisfy` |

Which operators return early:

| Operator | Returns or completes | Cancels upstream |
|---|---|---|
| `first()` | After the first value, or `nil` when the flow completes empty | Yes (see note) |
| `first(where:)`, `contains(where:)` | After the first match, or at completion | Yes (see note) |
| `allSatisfy(_:)` | At the first failing value, or at completion | Yes (see note) |
| `prefix(_:)`, `prefix(while:)` | After `n` values, or at the first failing value | Yes (see note) |
| `toArray()`, `last()`, `count()`, `reduce` | Only when the flow completes | No |
| `exactlyOne()` | Only when the flow completes. Throws `ExactlyOneError` if count is not 1 | No |
| `collect`, `collectLatest` | Only when the flow completes | No |
| `map`, `filter`, `compactMap`, `scan`, `dropFirst` | Complete when the upstream completes | No |
| `flatMap` | Collects each inner flow to its end, one after the other | No |
| `flatMap(maxConcurrent:)` | Runs up to `maxConcurrent` inner flows at the same time. On `Flow` only | No |
| `flatMapLatest`, `mapLatest`, `transformLatest` | Cancel the previous inner work when a new value comes | Inner only |
| `timeout(for:clock:)` | Throws `FlowTimeoutError` when the gap between values (and before the first) is too long. On `Flow` it returns a `ThrowingFlow` | Yes, on timeout |

`contains(where:)`, `allSatisfy(_:)`, `toArray()`, `last()`, `count()`, `reduce`, `exactlyOne()`
and `collectLatest` are on `Flow` only, not `ThrowingFlow`. `first()`, `first(where:)`,
`prefix(_:)` and `prefix(while:)` are on both. `collect` is on both.

```swift
import Flow

func firstThree(of source: Flow<Int>) async -> [Int] {
    await source.prefix(3).toArray()
}

func firstOrEmpty(of source: ThrowingFlow<[String]>) async throws -> [String] {
    try await source.first() ?? []
}
```

On a `ThrowingFlow`, `first()` and `first(where:)` are `async throws`, and the predicate can be
`async` and can throw.

- An error from the flow or from the predicate before the value is taken is rethrown.
- An error that the upstream throws after the value is taken is dropped. That includes the
  `CancellationError` of its own teardown.
- If the caller is cancelled before a value is taken, the call throws `CancellationError`. It does
  not return `nil`. `Flow.first()` returns `nil` in that case.

> **Note.** In 2.4.1 and earlier, `first()`, `first(where:)`, `contains(where:)`,
> `allSatisfy(_:)`, `prefix(_:)` and `prefix(while:)` do not cancel the upstream.
> They keep collecting until the flow completes. On a flow that stays open, they never
> return. Since 2.4.2, they cancel the upstream and wait for its teardown (for example
> `awaitClose`) before they return. On an earlier version, put a timeout around them.

- A flow that never emits and never completes keeps `first()` suspended forever. That is a
  property of the flow. Wrap the call in a timeout when the source can stay silent.
- Cancellation is cooperative. An operator that cancels the upstream also waits for it to
  end. A producer that ignores cancellation keeps the operator suspended.

```swift
import Flow

func resilient(_ source: ThrowingFlow<Int>) -> Flow<Int> {
    source
        .retry(3)
        .timeout(for: .seconds(5))
        .catch { _, collector in await collector.emit(-1) }
}

func latestOnly(_ source: Flow<Int>) -> Flow<Int> {
    source.buffer(size: 8, policy: .dropOldest)
}

func toThrowing(_ source: Flow<Int>) -> ThrowingFlow<Int> {
    source.mapThrowing { $0 }
}
```

### Limits of the operators

- `Flow.flatMapLatest` takes a closure that returns a `Flow`. Put `catch` inside that closure, on
  the inner `ThrowingFlow`. A `ThrowingFlow.flatMapLatest` over an upstream that stays open
  never ends when an inner flow fails, so a `catch` after it never runs.
- `combineLatest` takes at most five other flows. There is no overload for an array.
- A `ThrowingFlow` has no `buffer`, `keepingLatest`, `asSharedFlow`, `asStateFlow` or the
  `Flow`-only terminal operators above.

## callbackFlow and channelFlow

```swift
import Flow

final class LocationService: @unchecked Sendable {
    func observe(_ handler: @escaping @Sendable (Double) -> Void) -> Int { 1 }
    func remove(_ token: Int) {}
}

func locations(service: LocationService) -> Flow<Double> {
    Flow<Double>.callbackFlow { scope in
        let token = service.observe { scope.trySend($0) }
        await scope.awaitClose { service.remove(token) }
    }
}
```

- Other builders: `Flow(of: 1, 2, 3)` emits the values and completes. `Flow(sequence)` does the
  same for a `Sendable` sequence. `Flow.empty` completes at once. `Flow.never` never emits and never
  completes until the task is cancelled.
- `trySend` does not suspend and returns `.enqueued`, `.dropped` or `.closed`.
- `send` suspends only with `onBufferOverflow: .suspend` and a positive `bufferCapacity`.
  Otherwise it is the same as `trySend`. Under `.suspend`, `trySend` buffers without a bound.
- Defaults: `bufferCapacity: 64`, `onBufferOverflow: .dropOldest`. A capacity of zero or less
  is unbounded.
- `awaitClose(onClose)` suspends until the collector cancels, the collection ends or the
  block calls `close()`. Then it runs `onClose` one time.
- A `callbackFlow` block must end on `awaitClose` (or call `close()`). In debug builds an
  assertion fails if it returns without one of them.
- A `callbackFlow` that emits and then parks on `awaitClose` never completes. `toArray()`,
  `last()` and a `collect` to the end never return on it. `first()` returns after one value
  (since 2.4.2).

### A source that can fail

```swift
import Flow
import Foundation

final class Relay: @unchecked Sendable {
    init(
        onChunk: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable ((any Error)?) -> Void
    ) {}
    func cancel() {}
}

func chunks() -> ThrowingFlow<Data> {
    ThrowingFlow<Data>.callbackFlow(bufferCapacity: 0) { scope in
        let relay = Relay(
            onChunk: { scope.trySend($0) },
            onComplete: { error in
                if let error { scope.close(throwing: error) } else { scope.close() }
            }
        )
        await scope.awaitClose { relay.cancel() }
    }
}
```

- `ThrowingFlow.channelFlow` and `ThrowingFlow.callbackFlow` take the same parameters and
  defaults as the `Flow` builders. The block can throw and receives a `ThrowingProducerScope`.
- `close(throwing:)` ends the flow with an error. The collector receives every value sent
  before it, then `collect` throws the error. An error thrown from the block does the same.
- The first close wins. A later `close()` or `close(throwing:)` is ignored. `trySend` and
  `send` return `.closed` after it.
- A cancelled collector is not a failure. `onClose` runs one time, `collect` returns without
  an error, and an error the block throws while it tears down is dropped.
- `Flow.callbackFlow` and `ProducerScope` have no `close(throwing:)`. A `Flow` cannot fail.

## Hot flows

| Type | Holds | New collector receives | Completes |
|---|---|---|---|
| `MutableStateFlow(initial)` | One current value, read and written synchronously through `value` | The current value, then each distinct change | Only after `close()` |
| `MutableSharedFlow(replay: n)` | The last `n` values | The replay, then new values | Only after `close()` |

```swift
import Flow

func hotFlows() async {
    let state = MutableStateFlow(0)
    state.send(1)             // synchronous, no await
    state.value = 1           // equal to the current value: dropped
    state.update { $0 + 1 }

    let events = MutableSharedFlow<String>(replay: 1)
    events.tryEmit("from a delegate")      // no await, any thread
    await events.emit("from async code")

    let incoming = events.subscribed()     // registers the collector now
    await events.close()
    await incoming.collect { _ in }
}
```

- `MutableStateFlow` needs `Element: Equatable`. Setting an equal value does nothing.
  Collectors do not see it. `send(_:)` is synchronous. Do not write `await state.send(x)`.
  Use `update`, `getAndUpdate`, `updateAndGet` or `compareAndSet` for read-modify-write.
- `StateFlow` and `SharedFlow` are read-only protocols. Expose `any StateFlow<T>` from a type
  and keep the mutable flow private. `asStateFlow()` and `asSharedFlow()` with no arguments on a
  mutable flow give the read-only view.
- `MutableSharedFlow.emit` sends only to the collectors attached at that time. With
  `replay: 0`, a value emitted before a collector attaches is lost.
- `MutableSharedFlow.tryEmit(_:)` does the same work as `emit` with no `await`. Call it from a
  delegate method, a notification block or a C callback, from any thread. Calls made in order
  from one thread arrive in that order. It never waits for a collector. It returns `true`
  for every overflow policy the flow has today, and `false` only after `close()`. Do not start a
  `Task` for each event to call `emit`, because two such tasks are not ordered.
- `MutableSharedFlow` with `onBufferOverflow: .suspend` (the default) does not backpressure.
  The buffer of each subscriber is unbounded. `.dropOldest` and `.dropLatest` bound it to
  `replay + extraBufferCapacity` when that sum is greater than zero. A sum of zero stays
  unbounded.
- `replayCache` shows the replay. `resetReplayCache()` clears it. `subscriptionCount` is `async`.
- Read a hot flow with `.asFlow()`. A hot flow does not complete until its owner closes it,
  so use `first()`, `prefix(_:)` or a cancelled task to stop. `toArray()` on an open hot flow
  never returns.
- `close()` on `MutableStateFlow` (synchronous) or `MutableSharedFlow` (`await`) ends the
  flow. Each collector receives the values already sent to it, then `collect` returns. Close
  is final and safe to repeat. There is no reopen.
- After `close()`, `emit`, `tryEmit`, `send`, a write to `value` and the update family do
  nothing, and `tryEmit` returns `false`.
  `value` still reads the last value. A new collector of a closed `MutableSharedFlow` returns
  at once and gets no replay. A new collector of a closed `MutableStateFlow` receives the last
  value and then returns.
- `.asFlow()` registers its subscriber when a task starts to collect it. `subscribed()` on
  `MutableSharedFlow` and `MutableStateFlow` registers before it returns. It is synchronous.
  Values emitted after the call wait in the buffer of the subscriber until a task collects
  the returned flow. That flow can be collected one time. A second collection completes at
  once with no values. Release the flow without a collection, or cancel the collecting
  task, to remove the subscriber. A state flow gives the value from the time of
  registration first. A shared flow with a replay gives the replay first. There is no
  `onSubscription` operator. Use `subscribed()`.
- `close()` also ends a collection of a `subscribed()` flow, after the values already sent to
  it. `subscribed()` on a closed `MutableSharedFlow` gives a flow that completes at once with
  no values. On a closed `MutableStateFlow` it gives the last value and then completes.

### Share a cold flow

```swift
import Flow

struct Item: Sendable, Equatable { let id: Int }

protocol ItemRepository: Sendable {
    func search(_ query: String) -> ThrowingFlow<[Item]>
}

enum ItemState: Sendable, Equatable {
    case idle
    case loaded([Item])
    case failed
}

func makeResults(
    queries: MutableStateFlow<String>,
    repository: any ItemRepository
) -> any StateFlow<ItemState> {
    queries.asFlow()
        .debounce(for: .milliseconds(300))
        .removeDuplicates()
        .flatMapLatest { query -> Flow<ItemState> in
            guard !query.isEmpty else { return Flow(of: .idle) }
            // catch sits inside flatMapLatest, so one failure does not end the pipeline.
            return repository.search(query)
                .map { ItemState.loaded($0) }
                .catch { _, collector in await collector.emit(.failed) }
        }
        .asStateFlow(initialValue: .idle, strategy: .whileSubscribed(stopTimeout: .seconds(5)))
}
```

- `asStateFlow(initialValue:strategy:clock:)` and `asSharedFlow(replay:strategy:clock:)` are
  on `Flow` only. `asStateFlow` needs `Element: Equatable`. A `ThrowingFlow` must `catch`
  first. They share one upstream collection between collectors. The flows they return have no
  `close()`. The sharing strategy owns their lifetime.
- `.eager` starts at once. `.lazy` starts on the first collector and does not stop.
  `.whileSubscribed(stopTimeout:replayExpiration:)` is the default. Both durations
  default to `.zero`. The upstream then stops when the last collector leaves.
- With `.whileSubscribed` and `replayExpiration: .zero`, `asSharedFlow` clears its replay
  when the last collector leaves. `asStateFlow` keeps its value.

## Buffers and back-pressure

- No buffer: the producer waits for each `emit` to return.
- `buffer(size:policy:)`: `.suspend` makes the producer wait while the buffer is full.
  `.dropOldest` and `.dropLatest` drop values.
- `bufferUnbounded()` never drops and never suspends. `keepingLatest()` keeps only the newest
  value for a slow collector. `buffer(size:policy:)`, `bufferUnbounded()` and `keepingLatest()`
  are on `Flow` only.

## Sendable and isolation

- `Element` must be `Sendable`. Operator closures are `@Sendable`. Use the `Mutex` that
  `import Flow` exports, or an actor, for state that a closure changes.
- Core operators do not change isolation. FlowUI actions are `@MainActor` (see FlowUI.md).
- `FlowScope` holds tasks. `flow.launch(in: scope)` collects in a task of the scope and
  discards the values. Put the work in `onEach`. A `ThrowingFlow` swallows errors there.
  Handle them with `catch` first. `scope.cancel()` cancels all the tasks. A scope that is
  released cancels its tasks.

```swift
import Flow

final class Tracker: @unchecked Sendable {
    let scope = FlowScope()

    func start(_ source: Flow<Int>) {
        // Capture self weakly: the scope holds the task and the task holds the closure.
        source
            .onEach { [weak self] value in self?.handle(value) }
            .launch(in: scope)
    }

    func handle(_ value: Int) {}

    deinit { scope.cancel() }
}
```

## Traps (wrong, then right)

| Trap | Wrong | Right |
|---|---|---|
| Wait for completion of an open flow | `await callbackFlow.toArray()` | `await callbackFlow.prefix(3).toArray()` |
| Silent source | `await silent.first()` | Wrap it in `withThrowingTimeout` with a `TestClock` (see FlowTesting.md). |
| Emit before a collector attaches | `await shared.emit(1); Task { await shared.asFlow().collect { ... } }` | Start the collector, `try await shared.waitForSubscribers(1)`, then emit. |
| Start a producer after `Task { }` and expect its first event | `Task { await shared.asFlow().collect { ... } }; connection.start()` | `let incoming = shared.subscribed()`, then `Task { await incoming.collect { ... } }`, then `connection.start()`. |
| Expect a repeat on a state flow | `state.value = 1; state.value = 1` and expect two values | One value. Equal values are dropped. |
| `await` on a state flow write | `await state.send(1)` | `state.send(1)`. It is synchronous. |
| Expect `.suspend` to slow a shared emitter | `MutableSharedFlow(onBufferOverflow: .suspend)` | Use `buffer(size:policy: .suspend)` on a cold flow, or `channelFlow(onBufferOverflow: .suspend)` with `send`. |
| Real time in a test | `try await Task.sleep(for: .milliseconds(300))` | `await clock.advance(by: .milliseconds(300))` with a `TestClock` |
| Callback bridge with no teardown | `callbackFlow { scope in register { scope.trySend($0) } }` | End the block with `await scope.awaitClose { unregister() }` |
| Failure from a callback bridge | `Flow<Result<Data, any Error>>.callbackFlow { ... }` and unwrap downstream | `ThrowingFlow<Data>.callbackFlow` and `scope.close(throwing: error)` |
| Share by collecting twice | Two `collect` calls on one cold `Flow` | Two runs of the body. `asSharedFlow` and `asStateFlow` are on `Flow` only. A `ThrowingFlow` must `catch` first. |
| `catch` after `flatMapLatest` on a `ThrowingFlow` | `.mapThrowing { $0 }.flatMapLatest { ... }.catch { ... }` | Use the `Flow` overload of `flatMapLatest` and `catch` inside the closure. |
