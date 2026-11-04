---
name: flowkit
description: How FlowKit flows behave in code that uses them. Use when you write, change, review or test Swift code that uses Flow, ThrowingFlow, callbackFlow, channelFlow, MutableStateFlow, MutableSharedFlow, asStateFlow, asSharedFlow or the FlowTesting module.
---

# FlowKit

FlowKit gives Swift a cold stream type (`Flow`, `ThrowingFlow`) and two hot types
(`MutableStateFlow`, `MutableSharedFlow`). The facts below come from the source and the tests
of the package. Products: `Flow` (core and operators), `FlowTesting` (test helpers),
`FlowUI` (SwiftUI and UIKit bindings).

## Flow is not AsyncStream

| | `Flow` / `ThrowingFlow` | `AsyncStream` |
|---|---|---|
| Start | The body runs only when you call `collect`. | The producer runs when you make the stream. |
| Collectors | Each `collect` runs the body again, independently. | One consumer. |
| Replay | None. A new collector starts from the beginning. | None. |
| Multicast | Only after `asStateFlow` or `asSharedFlow`. | No. |
| Failure | `Flow` cannot fail. `ThrowingFlow` can. | `AsyncThrowingStream` for failure. |

- `collect` returns only when the body returns. A body that never returns makes `collect`
  suspend until the task is cancelled.
- `collector.emit(value)` calls the downstream action directly and suspends until it returns.
  Thus, with no `buffer`, a slow collector slows the producer.
- There is no scheduler hop. The body runs in the task that collects. `observe(on:)`,
  `receive(on:)` and `subscribeOn` are unavailable. Isolate the collecting side with an actor
  or `@MainActor`.
- Bridge: `flow.asAsyncStream()` collects in a new task, buffers without limit and cancels
  the collection when the consumer stops. A `Sendable` `AsyncSequence` becomes a flow with
  `asFlow()` (when it cannot fail) or `asThrowingFlow()`.

## Operators: which return early

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
| `flatMap(maxConcurrent:)` | Runs up to `maxConcurrent` inner flows at the same time | No |
| `flatMapLatest`, `mapLatest`, `transformLatest` | Cancel the previous inner work when a new value comes | Inner only |
| `timeout(for:clock:)` | Throws `FlowTimeoutError` when the gap between values (and before the first) is too long. On `Flow` it returns a `ThrowingFlow` | Yes, on timeout |

> **Note.** In 2.4.1 and earlier, `first()`, `first(where:)`, `contains(where:)`,
> `allSatisfy(_:)`, `prefix(_:)` and `prefix(while:)` keep the first value but continue to
> collect until the flow completes. On a flow that stays open, they never return. Since the
> release that contains the fix, they cancel the upstream and wait for its teardown (for
> example `awaitClose`) before they return. On an earlier version, put a timeout around them.

- A flow that never emits and never completes keeps `first()` suspended forever. That is a
  property of the flow. Wrap the call in a timeout when the source can stay silent.
- Cancellation is cooperative. An operator that cancels the upstream also waits for it to
  end, so a producer that ignores cancellation keeps the operator suspended.

## callbackFlow and channelFlow

```swift
let locations = Flow<CLLocation>.callbackFlow { scope in
    let token = service.observe { scope.trySend($0) }
    await scope.awaitClose { service.remove(token) }
}
```

- `trySend` does not suspend and returns `.enqueued`, `.dropped` or `.closed`.
- `send` suspends only with `onBufferOverflow: .suspend` and a positive `bufferCapacity`.
  Otherwise it is the same as `trySend`.
- Defaults: `bufferCapacity: 64`, `onBufferOverflow: .dropOldest`. A capacity of zero or less
  is unbounded.
- `awaitClose(onClose)` suspends until the collector cancels, the collection ends or the
  block calls `close()`. Then it runs `onClose` one time.
- A `callbackFlow` block must end on `awaitClose` (or call `close()`). In debug builds an
  assertion fails if it returns without one of them.
- A `callbackFlow` that emits and then parks on `awaitClose` never completes. `toArray()`,
  `last()` and a `collect` to the end never return on it. `first()` returns after one value
  (since the fix).

## Hot flows

| Type | Holds | New collector receives | Completes |
|---|---|---|---|
| `MutableStateFlow(initial)` | One current value, read and written synchronously through `value` | The current value, then each distinct change | Never |
| `MutableSharedFlow(replay: n)` | The last `n` values | The replay, then new values | Never |

- `MutableStateFlow` needs `Element: Equatable`. Setting an equal value does nothing, so
  collectors do not see it. Use `update`, `getAndUpdate`, `updateAndGet` or `compareAndSet`
  for read-modify-write.
- `MutableSharedFlow.emit` sends only to the collectors attached at that time. With
  `replay: 0`, a value emitted before a collector attaches is lost.
- `MutableSharedFlow` with `onBufferOverflow: .suspend` (the default) does not backpressure.
  The buffer of each subscriber is unbounded. `.dropOldest` and `.dropLatest` bound it to
  `replay + extraBufferCapacity`.
- Read a hot flow with `.asFlow()`. Because hot flows never complete, use `first()`,
  `prefix(_:)` or a cancelled task to stop. `toArray()` on a hot flow never returns.
- `asStateFlow(initialValue:strategy:clock:)` and `asSharedFlow(replay:strategy:clock:)`
  share one upstream collection between collectors. `SharingStrategy`: `.eager` starts at
  once, `.lazy` starts on the first collector and does not stop, `.whileSubscribed(stopTimeout:replayExpiration:)`
  (the default, both `.zero`) stops the upstream after the last collector leaves.
- With `.whileSubscribed` and `replayExpiration: .zero`, `asSharedFlow` clears its replay
  when the last collector leaves. `asStateFlow` keeps its value.

## Buffers and back-pressure

- No buffer: the producer waits for each `emit` to return.
- `buffer(size:policy:)`: `.suspend` makes the producer wait while the buffer is full.
  `.dropOldest` and `.dropLatest` drop values.
- `bufferUnbounded()` never drops and never suspends. `keepingLatest()` keeps only the newest
  value for a slow collector.

## Sendable and isolation

- `Element` must be `Sendable`. Operator closures are `@Sendable`. Use the `Mutex` that
  `import Flow` exports, or an actor, for state that a closure changes.
- FlowUI actions (`ViewExtensions`, `UIViewControllerExtensions`, `AppKitExtensions`) are
  `@MainActor`. Core operators do not change isolation.
- `FlowScope` holds tasks. `flow.launch(in: scope)` collects in a task of the scope and
  discards the values, so put the work in `onEach`. `scope.cancel()` cancels all the tasks.

## Testing without sleeps (`FlowTesting`)

| API | What it does |
|---|---|
| `flow.probing { reader in ... }` | Collects in a task and gives a `FlowReader`. `expectValue`, `expectNextValue`, `expectCompletion`, `expectError` suspend on the next event of the flow, with no deadline. The collection is cancelled when the block exits. Preferred. |
| `TestClock` | A `Clock` that moves only when the test calls `advance(by:)` or `advance(to:)`. `waitForSleepers(_:)` waits until that many sleeps are registered. Pass it to `debounce`, `throttle`, `sample`, `timeout`, `retry` and the sharing strategies. |
| `withThrowingTimeout(_:clock:_:)` | Runs a body and throws `FlowTestError.timeout` when the clock passes the duration. With a `TestClock` the deadline moves only on `advance`. The form without `clock:` uses real time, scaled by `FLOWKIT_TIMEOUT_SCALE`. |
| `flow.test(timeout:clock:_:)` | Gives a `FlowTester` (`expectValue`, `expectNoValue(within:)`, `expectCompletion`, `receivedValues`). Use it when the test must prove that nothing arrived in a time. The form without `clock:` is deprecated. |
| `TestScope.run(timeout:clock:_:)` | Collects more than one flow, each with its own tester, and cancels all of them at the end. The form without `clock:` is deprecated. |
| `FlowProbe` | Records values and `waitForValue(where:)` suspends until one matches. `flow.tap(after: probe)` records the values that pass. |
| `waitUntil(timeout:clock:_:)` | Polls a condition. The form without `clock:` is deprecated. Prefer `probing` or `waitForSubscribers`. |
| `waitForSubscribers(_:)`, `waitForSubscribers(atMost:)` | On `MutableStateFlow` and `MutableSharedFlow`. Suspend until enough collectors attach or leave. Use this before you emit into a shared flow. |

- A `FlowReader` read on a producer that stays open and never emits again parks until the
  test is cancelled. Make each emission depend on an action of the test.

## Traps (wrong, then right)

All of these come from the source code above.

| Trap | Wrong | Right |
|---|---|---|
| Wait for completion of an open flow | `await callbackFlow.toArray()` | `await callbackFlow.prefix(3).toArray()` |
| Silent source | `await silent.first()` | `try await withThrowingTimeout(.seconds(5)) { await silent.first() }` |
| Emit before a collector attaches | `await shared.emit(1); Task { await shared.asFlow().collect { ... } }` | Start the collector, `try await shared.waitForSubscribers(1)`, then emit. |
| Expect a repeat on a state flow | `state.value = 1; state.value = 1` and expect two values | One value. Equal values are dropped. |
| Expect `.suspend` to slow a shared emitter | `MutableSharedFlow(onBufferOverflow: .suspend)` | Use `buffer(size:policy: .suspend)` on a cold flow, or `channelFlow(onBufferOverflow: .suspend)` with `send`. |
| Real time in a test | `try await Task.sleep(for: .milliseconds(300))` | `await clock.advance(by: .milliseconds(300))` with a `TestClock` |
| Callback bridge with no teardown | `callbackFlow { scope in register { scope.trySend($0) } }` | End the block with `await scope.awaitClose { unregister() }` |
| Share by collecting twice | Two `collect` calls on one cold `Flow` | Two runs of the body. Use `asSharedFlow` or `asStateFlow` to share. |
