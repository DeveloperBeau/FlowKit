# FlowTesting and FlowRecording

`import FlowTesting` re-exports `TestClock`, `FlowTestError`, `TestScope` and the testers. It links
the `Testing` framework. Use it in a test target. Do not import the module `FlowTestClock`. It is
not a product.

## Testing without sleeps

| API | What it does |
|---|---|
| `flow.probing { reader in ... }` | Collects in a task and gives a `FlowReader`. `awaitValue`, `expectValue`, `expectNextValue`, `expectCompletion`, `expectError` suspend on the next event of the flow, with no deadline. `cancelAndIgnoreRemaining()` drops values that no read took. The collection is cancelled when the block exits. Preferred. |
| `TestClock` | A `Clock` that moves only when the test calls `advance(by:)` or `advance(to:)`. `run()` wakes every sleeper in deadline order until none remain. `now` and `sleeperCount` read the state. `waitForSleepers(_:)` waits until that many sleeps are registered. `waitForSleepers(atMost:)` waits until at most that many remain, and `waitForNoSleepers()` waits until none remain (for example after a cancelled operator tears down its sleep). Pass it to `debounce`, `throttle`, `sample`, `timeout`, `asStateFlow` and `asSharedFlow`. |
| `withThrowingTimeout(_:clock:_:)` | Runs a body and throws `FlowTestError.timeout` when the clock passes the duration. With a `TestClock` the deadline moves only on `advance`. The form without `clock:` uses real time, scaled by `FLOWKIT_TIMEOUT_SCALE`. |
| `flow.test(timeout:clock:_:)` | Gives a `FlowTester` (`expectValue`, `expectNoValue(within:)`, `expectCompletion`, `receivedValues`), or a `ThrowingFlowTester` for a `ThrowingFlow`. Use it when the test must prove that nothing arrived. `expectNoValue(within:)` measures that gap on the real clock. `expectValue`, `awaitValue` and `expectCompletion` take a `within:` limit, 5 seconds by default. The form without `clock:` is deprecated. |
| `TestScope.run(timeout:clock:_:)` | Collects more than one flow, each with its own tester, and cancels all of them at the end. The form without `clock:` is deprecated. |
| `FlowProbe` | Records values and `waitForValue(where:)` suspends until one matches. `flow.tap(after: probe)` records the values that pass. |
| `waitUntil(timeout:clock:_:)` | Polls a condition. The form without `clock:` is deprecated. Prefer `probing` or `waitForSubscribers`. |
| `waitForSubscribers(_:)`, `waitForSubscribers(atMost:)` | On `MutableStateFlow` and `MutableSharedFlow`. Suspend until enough collectors attach or leave. Use this before you emit into a shared flow. |

- `FlowTestError` has the cases `timeout`, `unexpectedCompletion` and `unexpectedValue`. A read that
  fails throws `FlowReaderError.flowEnded` or `.unexpectedValue`.
- `FLOWKIT_TIMEOUT_SCALE` multiplies every real-time limit. It is read one time. A value below 1
  becomes 1. A `TestClock` deadline ignores it. With `xcodebuild`, pass it as
  `TEST_RUNNER_FLOWKIT_TIMEOUT_SCALE`.
- A `FlowReader` read on a producer that stays open and never emits again parks until the
  test is cancelled. Make each emission depend on an action of the test.

### Debounce with a TestClock

```swift
import Testing
import Flow
import FlowTesting

@Test func debounceEmitsTheLastValue() async throws {
    let clock = TestClock()
    let queries = MutableSharedFlow<String>()
    try await queries.asFlow()
        .debounce(for: .milliseconds(300), clock: clock)
        .probing { reader in
            try await queries.waitForSubscribers(1)
            await queries.emit("s")
            await queries.emit("swift")
            try await clock.waitForSleepers(1)
            await clock.advance(by: .milliseconds(300))
            try await reader.expectValue("swift")
        }
}
```

A debounce on a `MutableStateFlow` registers a timer for the first value too. If the test sets the
query after collection starts, `waitForSleepers(1)` can match the timer of the old value. Set the
query before `probing`, or use a `MutableSharedFlow` and `emit`.

### Hot flows and equal values

```swift
import Testing
import Flow
import FlowTesting

@Test func stateFlowDropsEqualValues() async throws {
    let state = MutableStateFlow(0)
    try await state.asFlow().probing { reader in
        try await reader.expectValue(0)
        state.send(1)
        state.send(1)   // equal to the current value: dropped
        state.send(2)
        try await reader.expectValue(1)
        try await reader.expectNextValue(2)
    }
}
```

### Failures

```swift
import Testing
import Flow
import FlowTesting

struct Boom: Error, Equatable {}

@Test func failureIsRead() async throws {
    let source = ThrowingFlow<Int> { collector in
        try await collector.emit(1)
        throw Boom()
    }
    try await source.probing { reader in
        try await reader.expectValue(1)
        try await reader.expectError("boom") { ($0 as? Boom) == Boom() }
    }
}
```

### More than one flow

```swift
import Testing
import Flow
import FlowTesting

@Test func twoFlowsInOneScope() async throws {
    let clock = TestClock()
    try await TestScope.run(clock: clock) { scope in
        let numbers = try await scope.test(Flow(of: 1, 2))
        let words = try await scope.test(Flow(of: "x"))
        try await numbers.expectValue(1)
        try await numbers.expectValue(2)
        try await words.expectValue("x")
    }
}
```

### A silent source

`silent` never emits. The timeout runs on the `TestClock`, so the test takes no real time.

```swift
import Testing
import Flow
import FlowTesting

@Test func silentSourceTimesOut() async throws {
    let clock = TestClock()
    let silent = Flow<Int>.never
    let task = Task {
        try await withThrowingTimeout(.seconds(5), clock: clock) {
            await silent.first()
        }
    }
    try await clock.waitForSleepers(1)
    await clock.advance(by: .seconds(5))
    await #expect(throws: FlowTestError.timeout) { try await task.value }
}
```

## Limits and gotchas

- A test that reads a mock must wait until the code under test has started it. Give the mock a
  signal, for example an `AsyncStream<Void>` that it yields when started. A value that the mock
  sends before the delegate is set is lost.
- A bridge that checks `authorizationStatus` must read the status of the manager it receives, not
  a new `CLLocationManager()`. A mock never passes the second check.
- `probing` has no deadline. A flow that never emits makes the test wait until the test is
  cancelled. The Swift Testing time limit is the only bound. Use `withThrowingTimeout` with a
  `TestClock` when the test must fail on silence.
- `FlowTesting` has no fake for `Task.sleep`. Inject a `Clock` into the code under test.

## Recording outside a test bundle (`FlowRecording`)

`FlowTesting` links the `Testing` framework, so a module that imports it cannot be linked into
a UI-test host app, a preview target or a fixture executable. `FlowRecording` depends on
`Flow` only. Use it in shared test-support code that those targets link.

```swift
import Flow
import FlowRecording

func record() async -> [Int] {
    let source = MutableStateFlow(0)
    let recorder = FlowRecorder(source.asFlow())   // collection starts here
    try? await source.waitForSubscribers(1)
    source.send(1)
    let values = await recorder.values(atLeast: 2) // [0, 1]
    recorder.cancel()
    return values
}
```

- `FlowRecorder(_:)` takes a `Flow` or a `ThrowingFlow` and collects it in a task from `init`.
  With a hot flow, wait for `waitForSubscribers(1)` before you emit.
- `values` is every value so far, in emission order. `isFinished` is `true` after the flow
  completed or failed, or after `cancel()`. `failure` is the error of a `ThrowingFlow`.
- `values(atLeast:)` returns the whole record when it holds that many values. It returns what
  it has when the flow ends first, after `cancel()`, or when the waiting task is cancelled.
  It does not throw.
- It has no assertion, no timeout and no clock. A wait on a flow that stays open and never
  emits again does not end by itself. The caller bounds it.
- `cancel()` and release of the recorder both cancel the collection. A value or an error
  that arrives after `cancel()` is dropped.
- The record is unbounded. Do not use it in production code.
- In a test target that can link `FlowTesting`, `probing` is still the tool.
