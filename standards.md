# Standards

These are the rules for FlowKit. They describe the package as it is kept. Where the current sources break a rule, the exception is named at the end. This file does not change the code.

The API catalogue is the DocC site, [Flow](https://developerbeau.github.io/FlowKit/documentation/flow/). These notes say how the modules fit together and what a change has to satisfy. They do not restate the catalogue.

## Testing

1. `swift test` from the repo root passes from a clean checkout. Each pull request body carries that real output, plus the real output of `swift test -c release`, plus any iOS or Android build the change touches. No test is skipped, disabled, or flaky.

2. Tests assert behaviour a caller can observe, not internals.

3. Every new public API has at least one happy-path test and one failure-path test.

4. Every bug fix ships with a regression test that fails without the fix.

5. Coverage is reported for changed modules. None drops below the previous merged pull request. Coverage is a floor, not proof. A test that cannot fail counts for nothing.

6. Every feature, every seam, and every complete data flow has a success test, a failure test, and a fuzz test. A seam is each protocol boundary between modules. A fuzz test feeds generated or mutated input and checks both directions. Bad input is never accepted. Valid input is never rejected. Fuzz tests are seeded and print the seed.

7. Mutation testing runs on every pull request that changes module code under test. Each mutation breaks code on purpose and names the test expected to fail. The run confirms that test fails, restores the code, and records the result in the pull request. Any surviving mutant in changed code is killed by a new test or explained. The branch is brought up to date with the default branch before the run. A change that does not touch module code skips this check and says so.

8. Values that cross a module boundary have an end-to-end test checked against a hand-written expected result. No test asserts on a value it produced by calling the code under test.

9. Every wait is bounded. A hang fails with a name that says what hung. Test names say what they prove. A flaky test is a defect. Fix the cause. Never retry it or skip it.

10. Every module has its own tests and builds and tests alone. Tests cover the success path, developer misuse, and adversarial cases where they apply. Those cases include races, teardown, runs exactly once, and bounded memory.

11. Time, clock, random, network, file system, secrets, and storage reach code only through protocols. Tests use doubles and never call a real service.

12. Modules depend only inward. An automated architecture test should enforce this. It does not exist yet. An outward or sideways dependency is still a violation.

13. No published API is removed or changed in behaviour without a documented breaking change and a matching version bump. Record that break in `CHANGELOG.md`. New public surface has docs. No new third-party dependency without the owner's approval.

14. Tests read flows with `probing` or a `TestClock` and never use wall-clock sleeps as the pass condition. Time-based operators are driven by the injected clock. An operator that has its answer cancels upstream. `first`, `prefix`, and the like are that case. When a test has to prove that a flow stayed quiet, pass a `TestClock` to `test(timeout:clock:_:)`, `TestScope.run(timeout:clock:_:)`, `withThrowingTimeout(_:clock:_:)`, or `waitUntil(timeout:clock:_:)`. `Flow` and `FlowTesting` keep building for the Android triples when a change touches them. `FlowUI` stays Apple-only.

## Architecture

The products are `Flow`, `FlowTesting`, and `FlowUI`. `Flow` is the core. `FlowTesting` and `FlowUI` depend on it. `Flow` does not depend on either of them. `FlowTesting` and `FlowUI` do not depend on each other.

The targets inside those products, as `Package.swift` declares them:

| Ring | Target | Depends on |
|---|---|---|
| 0 | `FlowSharedModels` | nothing |
| 1 | `FlowCore` | `FlowSharedModels` |
| 1 | `FlowTestClock` | `FlowSharedModels` |
| 2 | `FlowOperators` | `FlowCore`, AsyncAlgorithms |
| 3 | `FlowHotStreams` | `FlowSharedModels`, `FlowCore`, `FlowOperators` |
| 3 | `Flow` | `FlowSharedModels`, `FlowCore`, `FlowOperators`, `FlowHotStreams` |
| 4 | `FlowTestingCore` | `Flow`, `FlowTestClock` |
| 4 | `FlowTesting` | `FlowTestClock`, `FlowTestingCore` |
| 4 | `FlowSwiftUI` | `FlowSharedModels`, `FlowCore`, `FlowHotStreams`, `Flow` |
| 4 | `FlowUIKitBridge` | `FlowCore`, `FlowHotStreams` |
| 5 | `FlowUI` | `FlowSwiftUI`, `FlowUIKitBridge`, `Flow` |

`Flow`, `FlowTesting`, and `FlowUI` are umbrella targets. Each one re-exports the targets named in its source file. `FlowTestSupport` and the test targets sit outside the products and depend inward on the modules they exercise.

`FlowSharedModels` holds `Mutex`, `BufferOverflow`, `SharingStrategy`, and `FlowTestError`. `FlowTestError` is part of the `Flow` product because the umbrella re-exports `FlowSharedModels`. Its doc comment says why it lives there.

One public type per file, and the file is named after that type. There is no hidden global state. A required dependency is an argument of the initializer or the method that uses it, and that argument has no default. One type owns each decision: `MutableStateFlow` owns its current value, `MutableSharedFlow` owns its replay buffer, `SharingCoordinator` owns when a shared upstream starts and stops, `FlowScope` owns the tasks launched in it, and `TestClock` owns its instant.

The third-party packages already in `Package.swift` are `swift-async-algorithms` 1.1.5 (used by `FlowOperators`), `swift-docc-plugin` 1.5.0 (documentation tooling), and `swift-crypto` 5.0.0 (the `FlowSimulationTests` target only).

## API style

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). The name is clear at the call site. Names are roles. A Boolean reads as an assertion. A capability protocol ends in `-ing` or `-able`. Every public declaration has a one-sentence doc comment. The public surface stays as small as the job allows.

`FlowUI` sources compile only where SwiftUI, Observation, UIKit, or AppKit can be imported. A green Android build of `FlowUI` would be an empty module, so it is not a product there.

## Pull requests

A pull request is small enough to review in one sitting. What the body must show is rule 1.

Sign the commit as the engineer who wrote it. Leave off a co-author trailer and a generated-by trailer.

## Docs

Write short plain sentences. Prose has no semicolons and no em dashes. Docs and comments carry no absolute paths, no user names, and no computer names. A comment says why, and what the next reader cannot see from the code alone. Docs describe the code as it is.

`docs/` is the generated DocC site. Do not edit it by hand. Regenerate it in the same pull request as a change to `Sources/Core/Flow/Documentation.docc/`, using the command in `README.md`.

## Exceptions

The sources below break a rule in this file. They are recorded here and left as they are.

### More than one public type, or a type whose file has another name

- `Sources/Core/FlowCore/Flow/ChannelFlow.swift` holds `ChannelSendResult` and `ProducerScope`. The file is named for `channelFlow` and `callbackFlow`.
- `Sources/Core/FlowCore/Flow/Flow.swift` holds `Flow` and the nested `Body` typealias.
- `Sources/Core/FlowCore/ThrowingFlow/ThrowingFlow.swift` holds `ThrowingFlow` and the nested `Body` typealias.
- `Sources/Core/FlowOperators/Terminal.swift` holds `ExactlyOneError` beside the terminal operators.
- `Sources/Core/FlowOperators/Timeout.swift` holds `FlowTimeoutError` beside `timeout(for:clock:)`.
- `Sources/Testing/FlowTestingCore/Testers/FlowReader.swift` holds `FlowReader` and `FlowReaderError`.
- `Sources/Testing/FlowTestClock/TestClock.swift` holds `TestClock`, the nested `Instant`, and `Duration`. `Instant` and `Duration` are what `Clock` requires.
- `Sources/UI/FlowSwiftUI/ObservedStateFlow.swift` holds `ObservedStateFlow` and the nested `UpdatePolicy`.
- `Sources/Core/FlowHotStreams/MigrationShims.swift` holds six unavailable typealiases: `PublishSubject`, `BehaviorSubject`, `BehaviorRelay`, `ReplaySubject`, `CurrentValueSubject`, and `PassthroughSubject`.
- `Sources/Core/FlowOperators/MigrationShims.swift` holds the unavailable `Observable` typealias. The file is named for the migration shims.

Operator and builder files group many public methods by behaviour. They are `FlowBuilders.swift`, `ThrowingFlowBuilders.swift`, `FlowScope+Launch.swift`, `Transform.swift`, `Lifecycle.swift`, `Flattening.swift`, `Combining.swift`, `ErrorHandling.swift`, `RateLimiting.swift`, `Buffering.swift`, `Sharing.swift`, `AsyncSequenceBridge.swift`, `FlowTestExtensions.swift`, `ViewExtensions.swift`, `FlowObservingInit.swift`, `UIViewControllerExtensions.swift`, and `AppKitExtensions.swift`.

### Globals

- `Sources/Testing/FlowTestingCore/TimeoutHelpers.swift` publishes `flowTestTimeoutScale`. It is read once from the `FLOWKIT_TIMEOUT_SCALE` environment variable.
- `Sources/UI/FlowUIKitBridge/UIViewControllerExtensions.swift` has a private `flowScopeKey`. It is a stable pointer for an associated object and holds no mutable data.
- `Sources/UI/FlowUIKitBridge/AppKitExtensions.swift` has private `nsViewControllerFlowScopeKey` and `nsWindowControllerFlowScopeKey`, for the same reason.

### Time that does not go through a clock

- `Flow.never` in `Sources/Core/FlowCore/Flow/FlowBuilders.swift` suspends with `Task.sleep`.
- `waitUntil` in `Sources/Testing/FlowTestingCore/WaitUntil.swift` polls with `Task.yield` and `Task.sleep`. The overload that takes a `Clock` measures its deadline on that clock. The poll itself does not.

### Dependency declared in source and not in the package manifest

Every import of a package target that `Package.swift` does not declare is listed here, for `Sources/` and for `Tests/`. Each one points inward. `Testing`, `Foundation`, `SwiftUI`, `UIKit`, `AppKit`, and `Observation` are not package targets. An architecture test would catch these, and none is in the repo.

- `FlowUIKitBridge` imports `FlowOperators` from `Sources/UI/FlowUIKitBridge/UIViewControllerExtensions.swift` and `Sources/UI/FlowUIKitBridge/AppKitExtensions.swift`, so those files can call `onEach`. The declared dependencies are `FlowCore` and `FlowHotStreams`. Those files are compiled only where UIKit or AppKit is present.
- `FlowOperators` imports `FlowSharedModels` from `Timeout.swift`, `Buffering.swift`, `Lifecycle.swift`, `Terminal.swift`, `Transform.swift`, and `RateLimiting.swift`. The declared dependencies are `FlowCore` and AsyncAlgorithms.
- `Sources/Testing/FlowTesting/FlowTesting.swift` has `@_exported import FlowSharedModels`. The declared dependencies are `FlowTestClock` and `FlowTestingCore`.
- `FlowTestingCore` imports `FlowSharedModels` from `TimeoutHelpers.swift`, `Testers/FlowTester.swift`, `Testers/FlowTesterBase.swift`, and `Testers/ThrowingFlowTester.swift`. The same target imports `FlowCore` from `TestScope.swift`, `Testers/FlowProbe.swift`, `Testers/FlowReader.swift`, `Testers/FlowTestExtensions.swift`, `Testers/FlowTester.swift`, and `Testers/ThrowingFlowTester.swift`. The declared dependencies are `Flow` and `FlowTestClock`. `Flow` re-exports both modules.

`FlowTestSupport` declares `FlowTesting`, `FlowTestClock`, and `FlowSharedModels`.

- `Tests/Support/FlowTestSupport/ProbeScope.swift` has `package import FlowCore` and `@testable import FlowTestingCore`.

Test targets. `FlowSharedModelsTests`, `FlowSimulationTests`, and `FlowPublicAPITests` import only modules `Package.swift` lists for them.

- `FlowCoreTests` declares `FlowCore`, `FlowTesting`, and `FlowTestSupport`. It imports `FlowSharedModels` from every `Flow` and `ThrowingFlow` test file except `Flow/RingBufferTests.swift`. It imports `FlowTestingCore` from `Flow/FlowLaunchTests.swift`, `Flow/FlowScopeTests.swift`, and `Flow/MemoryLeakTests.swift`.
- `FlowOperatorsTests` declares `FlowOperators`, `FlowHotStreams`, `FlowTesting`, `FlowTestClock`, and `FlowTestSupport`. Every test file imports `FlowCore`. Twenty-three of the thirty-seven test files also import `FlowSharedModels`.
- `FlowHotStreamsTests` declares `FlowHotStreams`, `FlowTesting`, and `FlowTestSupport`. It imports `FlowCore` from every test file except `SharedFlow/MulticastSubscriptionTests.swift`. It imports `FlowSharedModels` from every test file except that file and `StateFlow/StateFlowAtomicsTests.swift`. `SharedFlow/ReplayExpirationTests.swift`, `SharedFlow/SharingCoordinatorTests.swift`, and `WhileSubscribedDefaultTests.swift` also import `FlowTestClock` and `FlowTestingCore`.
- `FlowTestClockTests` declares `FlowTestClock`, `FlowTestingCore`, and `FlowTestSupport`. `TestClockSleeperWaiterTests.swift` imports `FlowSharedModels`.
- `FlowTestingCoreTests` declares `FlowTestingCore` and `FlowTestSupport`. It imports `FlowCore` from `TestScopeTests.swift`, `Testers/FlowProbeTests.swift`, `Testers/FlowReaderTests.swift`, `Testers/FlowTestExtensionsTests.swift`, `Testers/FlowTesterTests.swift`, and `Testers/ThrowingFlowTesterTests.swift`. It imports `FlowSharedModels` from those files except `Testers/FlowProbeTests.swift`, and also from `TimeoutHelpersTests.swift` and `WaitUntilTests.swift`. `Testers/FlowReaderTests.swift` imports `FlowHotStreams`. `TestScopeTests.swift`, `Testers/FlowTestExtensionsTests.swift`, `TimeoutHelpersTests.swift`, and `WaitUntilTests.swift` import `FlowTestClock`.
- `FlowTestingPublicAPITests` declares `FlowTesting`. `FlowTestingReachabilityTests.swift` imports `Flow`.
- `FlowUITests` declares `FlowUI`, `FlowTesting`, and `FlowTestSupport`. `AppKitBridgeTests.swift`, `UIKitBridgeTests.swift`, `FlowObservingTests.swift`, `ObservedStateFlowTests.swift`, and `ViewExtensionsTests.swift` import `FlowCore`. `AppKitBridgeTests.swift`, `UIKitBridgeTests.swift`, and `ObservedStateFlowTests.swift` import `FlowHotStreams`. `ViewExtensionsTests.swift` imports `FlowSharedModels`. `FlowObservingTests.swift`, `ObservedStateFlowTests.swift`, and `ViewExtensionsTests.swift` import `FlowSwiftUI`. `AppKitBridgeTests.swift` and `UIKitBridgeTests.swift` import `FlowUIKitBridge`.

### Clock arguments that default to ContinuousClock

A required clock is an argument, and the rule gives that argument no default. Removing these defaults would change published call sites, so they stay.

- `Flow.asStateFlow(initialValue:strategy:clock:)` and `Flow.asSharedFlow(replay:strategy:clock:)` in `Sources/Core/FlowHotStreams/Sharing.swift` default `clock` to `ContinuousClock()`.
- `debounce(for:clock:)`, `throttle(for:latest:clock:)`, and `sample(every:clock:)` on `Flow` and on `ThrowingFlow`, in `Sources/Core/FlowOperators/RateLimiting.swift`, default `clock` to `ContinuousClock()`.
- `timeout(for:clock:)` on `Flow` and on `ThrowingFlow`, in `Sources/Core/FlowOperators/Timeout.swift`, defaults `clock` to `ContinuousClock()`.
- The deprecated real-clock helpers do not take a clock. They pass `ContinuousClock()` inside the method: `Flow.test(timeout:_:)`, `ThrowingFlow.test(timeout:_:)`, `TestScope.run(timeout:_:)`, `withThrowingTimeout(_:_:)`, and `waitUntil(timeout:_:)`. The `clock:` overloads of those helpers require the clock. No other public `clock` parameter defaults to `ContinuousClock()`.

### Public declarations with no doc comment of their own

A doc comment on the type, or on a sibling overload, does not cover the declaration named here.

- `Sources/Core/FlowCore/Flow/Flow.swift`: `Body`, `init`, `collect`.
- `Sources/Core/FlowCore/ThrowingFlow/ThrowingFlow.swift`: `Body`, `init`, `collect`.
- `Sources/Core/FlowCore/Flow/FlowBuilders.swift`: both initializers, `empty`, `never`, `asFlow()`.
- `Sources/Core/FlowCore/ThrowingFlow/ThrowingFlowBuilders.swift`: both initializers, `empty`, `asThrowingFlow()`.
- `Sources/Core/FlowCore/Flow/FlowScope.swift`: `init`.
- `Sources/Shared/FlowSharedModels/Mutex.swift`: `init`.
- `Sources/Core/FlowOperators/Transform.swift`: both `map` overloads other than `mapThrowing`, both `compactMap`, both `filter`, both `transform`, both `prefix(_:)`, both `dropFirst`, and both `scan(_:_:)` overloads that take an initial value. The other methods in the file have doc comments, including `scan` that takes only an accumulator.
- `Sources/Core/FlowOperators/Lifecycle.swift`: `onStart` and `onEach` on `ThrowingFlow`. The `Flow` overloads have doc comments.
- `Sources/Core/FlowOperators/Timeout.swift`: `FlowTimeoutError.init`.
- `Sources/Core/FlowOperators/MigrationShims.swift`: `Observable` and the unavailable methods `subscribe`, `disposed`, `distinctUntilChanged`, `startWith`, `observe`, `subscribeOn`, `withLatestFrom`, `share`, `catchError`, `catchErrorJustReturn`, `sink`, `store`, `eraseToAnyPublisher`, `receive`, `tryMap`, `setFailureType`, `replaceEmpty`, and `handleEvents`. Each one carries an unavailable-attribute message and no doc comment.
- `Sources/Core/FlowHotStreams/MigrationShims.swift`: the six typealiases listed above. Each one carries an unavailable-attribute message and no doc comment.
- `Sources/Core/FlowHotStreams/StateFlow/StateFlow.swift`: the `asFlow()` requirement. The protocol and `value` have doc comments.
- `Sources/Core/FlowHotStreams/StateFlow/MutableStateFlow.swift`: `init`, `asFlow()`.
- `Sources/Core/FlowHotStreams/SharedFlow/SharedFlow.swift`: the protocol, `subscriptionCount`, and `asFlow()`.
- `Sources/Core/FlowHotStreams/SharedFlow/MutableSharedFlow.swift`: the actor, `init`, `subscriptionCount`, `emit`, `resetReplayCache`, `asFlow()`.
- `Sources/Core/FlowHotStreams/SharedFlow/SharingCoordinator.swift`: the actor, `init`, `activate`, `deactivate`, `subscriberDidDisappear`.
- `Sources/Testing/FlowTestClock/TestClock.swift`: `Instant` and its members (`Duration`, `offset`, `init`, `advanced(by:)`, `duration(to:)`, `<`), plus `TestClock.Duration`, `init`, `now`, `minimumResolution`, and `sleep(until:tolerance:)`. The `TestClock` type itself has a doc comment.
- `Sources/Testing/FlowTestingCore/Testers/FlowProbe.swift`: `last`, `init`, `record`.
- `Sources/Testing/FlowTestingCore/Testers/FlowTester.swift`: `init`, `recordValue`, `recordCompletion`, `awaitValue`, `expectValue`, `expectNoValue`, `expectCompletion`, `receivedValues`, `cancelAndIgnoreRemaining`. The actor has a doc comment.
- `Sources/Testing/FlowTestingCore/Testers/ThrowingFlowTester.swift`: `init`, `recordValue`, `recordCompletion`, `recordError`, `awaitValue`, `expectValue`, `expectNoValue`, `expectCompletion`, both `expectError` overloads, `receivedValues`, `cancelAndIgnoreRemaining`. The actor has a doc comment.
- `Sources/UI/FlowSwiftUI/CollectedState.swift`: `init`, `wrappedValue`, `update`.
- `Sources/UI/FlowSwiftUI/ObservedStateFlow.swift`: `value`, `UpdatePolicy`, `init`, `start`, `stop`.

### Known gap

Nothing fails the build when a file imports a target that `Package.swift` does not list.
