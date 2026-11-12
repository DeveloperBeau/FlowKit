# Operators

Operators live in `Sources/Core/FlowOperators`. The target depends on `FlowCore` and on AsyncAlgorithms. An operator returns a new `Flow` or `ThrowingFlow`. Its body collects the upstream and emits downstream. Nothing in the chain runs until some outer `collect`.

Most operators exist on both `Flow` and `ThrowingFlow`. The terminal operations `first`, `first(where:)`, `contains(where:)`, `allSatisfy`, `toArray`, `reduce`, `exactlyOne`, `collectLatest`, `last`, and `count` are on `Flow`. `prefix` is on both.

The name-by-name map from Kotlin Flow is the catalogue article [Kotlin Flow migration](https://developerbeau.github.io/FlowKit/documentation/flow/kotlinflowmigration). The groups below are the files.

| File | Operations |
|---|---|
| `Transform.swift` | `map`, `mapThrowing`, `compactMap`, `filter`, `filterIsInstance`, `transform`, `prefix`, `prefix(while:)`, `drop`, `dropFirst`, `scan`, `enumerated`, `chunks(ofCount:)` |
| `Flattening.swift` | `flatMap`, `flatMap(maxConcurrent:)`, `flatMapLatest`, `mapLatest`, `transformLatest` |
| `Combining.swift` | `zip`, `combineLatest` (two through six upstreams), `merge` |
| `Lifecycle.swift` | `onStart`, `onEach`, `onCompletion`, `onEmpty` |
| `ErrorHandling.swift` | `catch`, `retry`, `retryWhen` |
| `RateLimiting.swift` | `debounce`, `throttle`, `removeDuplicates`, `sample` |
| `Buffering.swift` | `buffer(size:policy:)`, `bufferUnbounded`, `keepingLatest` |
| `Timeout.swift` | `timeout(for:clock:)` |
| `Terminal.swift` | the `Flow` terminals listed above, plus `ExactlyOneError` |
| `MigrationShims.swift` | unavailable RxSwift and Combine names |

`debounce`, `throttle`, `sample`, and `timeout` take a `Clock` and default it to `ContinuousClock()`. `retry` and `retryWhen` do not take a clock. A backoff delay is whatever the `retryWhen` predicate does.

`timeout(for:clock:)` on `Flow` returns a `ThrowingFlow` and fails with `FlowTimeoutError` when the gap between values, including the gap before the first value, exceeds `duration`. On `ThrowingFlow` the upstream error still propagates.

`buffer(size:policy:)` with `.suspend` suspends the producer while the buffer is full. `.dropOldest` and `.dropLatest` drop. `bufferUnbounded()` does neither. `keepingLatest()` keeps the newest value for a slow collector.

## How a value moves

`emit` suspends until the downstream action returns, unless a buffer sits between them. `flatMap` collects each inner flow to the end, one after another. `flatMap(maxConcurrent:)` runs that many inners at once and holds the rest. `zip` pairs by position and completes when either side completes. `combineLatest` waits until every side has emitted once, then emits again whenever any side emits. `merge` forwards values from all sides as they arrive.

## Cancellation

An operator that has its answer cancels the upstream and waits until that upstream ends.

`first()`, `first(where:)`, `contains(where:)`, and `allSatisfy(_:)` do this through `collectUntilStopped`. So do `prefix(_:)` and `prefix(while:)` on `Flow` and on `ThrowingFlow`. A producer can emit once more before it sees the cancellation, and the stop action ignores that late value. A flow that never emits and never completes leaves `first()` suspended. A flow that completes without a match returns `nil` from `first()` and `false` from `contains(where:)`. An empty flow makes `allSatisfy` return `true`.

`flatMapLatest`, `mapLatest`, and `transformLatest` cancel the previous inner flow when a new upstream value arrives. `collectLatest` cancels the previous action the same way. `timeout` cancels the collection when it fails with `FlowTimeoutError`.

`toArray`, `reduce`, `exactlyOne`, `last`, `count`, `collect`, and `flatMap` wait until the upstream completes. They do not cancel early. On a `callbackFlow` parked on `awaitClose`, or on any hot flow, those calls do not return.

Cancellation is cooperative. The operator waits for the upstream body to finish, so a producer that ignores cancellation keeps the operator suspended.

`Sources/Core/FlowOperators/MigrationShims.swift` and `Sources/Core/FlowHotStreams/MigrationShims.swift` are compile-time rails. Every declaration is unavailable and calls `fatalError` if it were reached. They exist so an RxSwift or Combine name points at the FlowKit spelling. Nothing in those files runs.
