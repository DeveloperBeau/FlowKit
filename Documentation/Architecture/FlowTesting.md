# FlowTesting

`FlowTesting` is the test product. The umbrella re-exports `FlowSharedModels`, `FlowTestClock`, and `FlowTestingCore`. `FlowTestingCore` depends on the `Flow` product, so the testers sit outside the core and call inward. Production targets do not depend on this product.

`FlowTestError` (`timeout`, `unexpectedCompletion`, `unexpectedValue`) lives in `FlowSharedModels` so a test helper and `FlowTestClock` can share it without a cycle. The `Flow` umbrella re-exports it for that reason.

## Reading a flow

`Flow.probing(_:)` and `ThrowingFlow.probing(_:)` collect on a task and hand the test a `FlowReader`. Each read suspends until the flow emits, completes, or fails. There is no deadline, so a slow machine does not fail a correct test. A wrong value fails at the call site. If the flow ends before the expected value, the read throws `FlowReaderError.flowEnded` and every later read fails the same way, because the end is remembered.

The collection task is cancelled when the block returns.

`awaitValue`, `expectValue`, `expectNextValue`, `expectCompletion`, `expectError`, and `cancelAndIgnoreRemaining` are the reads. `expectNextValue` is how a test shows that nothing else arrived before a known later value, without sleeping.

A producer that stays open and never emits again cannot be told from a slow one. That read parks until the test is cancelled. It is the one hang this reader cannot name. Keep each emission tied to an action the test performs. When the test must prove a quiet stretch, use a clock deadline instead.

## Virtual time

`TestClock` is a `Clock`. Time moves only when the test calls `advance(by:)` or `advance(to:)`. `sleep(until:)` registers a sleeper. `waitForSleepers(_:)` suspends until that many sleepers are registered. `waitForSleepers(atMost:)` and `waitForNoSleepers()` wait until sleepers have gone. A cancelled wait throws `CancellationError`.

Pass the clock into `debounce`, `throttle`, `sample`, `timeout`, `asStateFlow`, and `asSharedFlow`. Advance it only after `waitForSleepers` shows the operator has registered its sleep. `sleeperCount` is the snapshot. The wait is the one to use.

`FlowProbe` stores the last value that passed `tap(after:)`. `waitForValue(where:)` suspends until that value matches. Use it to see that a clock-driven operator has taken an input before you advance.

`MutableStateFlow` and `MutableSharedFlow` offer `waitForSubscribers(_:)` and `waitForSubscribers(atMost:)`. Emit after the collector has attached.

## Deadlines

`withThrowingTimeout(_:clock:_:)`, `Flow.test(timeout:clock:_:)`, `ThrowingFlow.test(timeout:clock:_:)`, `TestScope.run(timeout:clock:_:)`, and `waitUntil(timeout:clock:_:)` measure the deadline on the clock. A `TestClock` expires them only when the test advances it. The duration is not scaled.

The overloads without a clock are deprecated. They use `ContinuousClock` and multiply the duration by `flowTestTimeoutScale`, which is read once from `FLOWKIT_TIMEOUT_SCALE` (default 1, and values below 1 are clamped to 1). They still work. New tests use `probing` or a `TestClock`.

`FlowTester` and `ThrowingFlowTester` are the recorders behind `test(timeout:clock:_:)`. `TestScope` collects several flows, each with its own tester, and cancels them when the block exits. `expectNoValue(within:)` is not deprecated: a quiet-flow check needs a clock, and `probing` cannot express one.

`waitUntil` still polls on a real cadence (`Task.yield`, then a 1ms `Task.sleep`) even when the deadline is a `TestClock`. Real time does not decide that overload's outcome. The poll is the exception in [standards.md](../../standards.md). Prefer `probing`, `waitForSleepers`, `waitForValue(where:)`, or `waitForSubscribers` so the test suspends on the event itself.
