# Standards

These are the rules for FlowKit. They describe the package as it is kept. Where the current sources break a rule, the exception is named at the end. This file does not change the code.

The API catalogue is the DocC site, [Flow](https://developerbeau.github.io/FlowKit/documentation/flow/). These notes say how the modules fit together and what a change has to satisfy. They do not restate the catalogue.

## Testing

Every feature, every seam, and every complete data flow has three tests: a success test, a failure test, and a seeded fuzz test. The fuzz test checks a false positive and a false negative. It prints the seed it ran with.

A value that crosses a module boundary has an end-to-end test. The expected result in that test is written by hand.

A wait has a bound. If the test hangs, the failure names the wait. Test names say what they prove. An assertion compares against a value the test wrote down. It does not compare against a value computed by the code under test.

A flaky test is a defect in the code or in the test. Rerunning it is not a fix.

Read a flow with `probing` and move time with `TestClock`. A passing test does not sleep on the wall clock. When a test has to prove that a flow stayed quiet, pass a `TestClock` to `test(timeout:clock:_:)`, `TestScope.run(timeout:clock:_:)`, `withThrowingTimeout(_:clock:_:)`, or `waitUntil(timeout:clock:_:)`.

An operator that has its answer cancels the upstream and waits for that upstream to end.

Coverage is a floor. A green coverage number does not replace the tests above.

A pull request that changes module code includes a mutation check. Break the code on purpose, name the test that should fail, confirm that it fails, restore the code, and record that result in the pull request. A change that does not touch module code skips this check and says so.

## Architecture

A module depends only inward. Nothing in an inner ring imports an outer ring.

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

An automated architecture test that fails the build when a target imports outward is not in the repo.

One public type per file, and the file is named after that type. There is no hidden global state. A required dependency is an argument of the initializer or the method that uses it, and that argument has no default. Time passes only through a `Clock`. One type owns each decision: `MutableStateFlow` owns its current value, `MutableSharedFlow` owns its replay buffer, `SharingCoordinator` owns when a shared upstream starts and stops, `FlowScope` owns the tasks launched in it, and `TestClock` owns its instant. A new third-party dependency needs the owner's approval before it is added.

The third-party packages already in `Package.swift` are `swift-async-algorithms` 1.1.5 (used by `FlowOperators`), `swift-docc-plugin` 1.5.0 (documentation tooling), and `swift-crypto` 5.0.0 (the `FlowSimulationTests` target only).

## API style

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). The name is clear at the call site. Names are roles. A Boolean reads as an assertion. A capability protocol ends in `-ing` or `-able`. Every public declaration has a one-sentence doc comment. The public surface stays as small as the job allows.

Published API stays stable across releases. Do not remove published API, and do not change its behaviour, without a documented breaking change and a version bump that matches that change. Record the break in `CHANGELOG.md`.

`Flow` and `FlowTesting` keep building for Android. `FlowUI` is Apple-only. Its sources compile only where SwiftUI, Observation, UIKit, or AppKit can be imported. A green Android build of `FlowUI` would be an empty module, so it is not a product there.

## Pull requests

A pull request is small enough to review in one sitting, and the body shows how it was checked.

The body includes the real output of `swift test` and `swift test -c release`. It also includes the real output of any platform build the change touches. A change to `Flow` or `FlowTesting` includes the Android cross-compile. A change to `FlowUI` says whether the Apple UI tests ran. A docs-only change still runs both test commands and says that no platform build was touched.

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

Every import below points inward. `Package.swift` does not list the imported target on the importing target. An architecture test would catch these, and none is in the repo.

- `FlowUIKitBridge` imports `FlowOperators` from `Sources/UI/FlowUIKitBridge/UIViewControllerExtensions.swift` and `Sources/UI/FlowUIKitBridge/AppKitExtensions.swift`, so those files can call `onEach`. The declared dependencies are `FlowCore` and `FlowHotStreams`. Those files are compiled only where UIKit or AppKit is present.
- `FlowOperators` imports `FlowSharedModels` from `Timeout.swift`, `Buffering.swift`, `Lifecycle.swift`, `Terminal.swift`, `Transform.swift`, and `RateLimiting.swift`. The declared dependencies are `FlowCore` and AsyncAlgorithms.
- `Sources/Testing/FlowTesting/FlowTesting.swift` has `@_exported import FlowSharedModels`. The declared dependencies are `FlowTestClock` and `FlowTestingCore`.
- `FlowTestingCore` imports `FlowSharedModels` from `TimeoutHelpers.swift`, `Testers/FlowTester.swift`, `Testers/FlowTesterBase.swift`, and `Testers/ThrowingFlowTester.swift`. The declared dependencies are `Flow` and `FlowTestClock`.

### Clock arguments that default to ContinuousClock

A required clock is an argument, and the rule gives that argument no default. Removing these defaults would change published call sites, so they stay.

- `Flow.asStateFlow(initialValue:strategy:clock:)` and `Flow.asSharedFlow(replay:strategy:clock:)` in `Sources/Core/FlowHotStreams/Sharing.swift` default `clock` to `ContinuousClock()`.
- `debounce(for:clock:)`, `throttle(for:latest:clock:)`, and `sample(every:clock:)` on `Flow` and on `ThrowingFlow`, in `Sources/Core/FlowOperators/RateLimiting.swift`, default `clock` to `ContinuousClock()`.
- `timeout(for:clock:)` on `Flow` and on `ThrowingFlow`, in `Sources/Core/FlowOperators/Timeout.swift`, defaults `clock` to `ContinuousClock()`.
- The deprecated real-clock helpers do not take a clock. They pass `ContinuousClock()` inside the method: `Flow.test(timeout:_:)`, `ThrowingFlow.test(timeout:_:)`, `TestScope.run(timeout:_:)`, `withThrowingTimeout(_:_:)`, and `waitUntil(timeout:_:)`. The `clock:` overloads of those helpers require the clock.

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

No test in `Tests/` walks the target graph. Nothing fails the build when a module imports outward, or when a file imports a target that `Package.swift` does not list.
