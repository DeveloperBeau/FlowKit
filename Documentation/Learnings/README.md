# Learnings

Each note has three parts. The trap is the old behaviour or the assumption that led to it. The finding is what the code actually did. The rule is the constraint that follows.

These notes come from the changelog and from the commits that fixed the behaviour. Nothing here is speculative. Caller-facing operator facts that are already in the DocC catalogue and in `skills/flowkit/SKILL.md` are not copied into this list.

## `first` and `prefix` kept collecting

Trap: `first()`, `first(where:)`, `contains(where:)`, `allSatisfy(_:)`, `prefix(_:)`, and `prefix(while:)` were treated as done once they had kept their value.

Finding: before 2.4.2 they went on collecting until the upstream completed. On a flow that emits and then stays open, such as a `callbackFlow` parked on `awaitClose`, they never returned. `prefix` on `Flow` and `ThrowingFlow` had the same shape, so the prefixed flow did not complete while the upstream stayed open.

Rule: an operator that has its answer cancels the upstream and waits for it to end. That is what 2.4.2 does, in `collectUntilStopped`. A flow that completes with no match still returns `nil` from `first()`. A flow that never emits and never completes still leaves `first()` suspended.

## A cancelled upstream could refill the replay cache

Trap: `asSharedFlow` with `.whileSubscribed` cleared its replay as soon as the last subscriber left.

Finding: before 2.4.1 a value that the cancelled upstream was still emitting could land after that reset and stay in the cache for the next subscriber.

Rule: the reset waits for the stopped upstream to finish, then clears the cache. An upstream that ignores cancellation delays the reset, and the next subscriber, until it returns.

## `replayExpiration` was ignored

Trap: `SharingStrategy.whileSubscribed(stopTimeout:replayExpiration:)` was read as clearing the shared replay `replayExpiration` after the last subscriber left.

Finding: before 2.4.0 the parameter was ignored and the replay was never cleared. The next subscriber received stale values. The default `replayExpiration: .zero` now clears the cache before the leaving collection returns. Code that relied on the replay surviving a gap with no subscribers has to pass a long `replayExpiration`.

Rule: `asSharedFlow` honours `replayExpiration`. `asStateFlow` keeps its value. The 2.4.0 changelog records the behaviour change.

## `View.collecting` failed to link in release

Trap: `View.collecting` returned SwiftUI's `.task` modifier directly.

Finding: before 2.2.0 a release build resolved that to the newer `task(name:priority:file:line:_:)` overload. The client module then referenced that overload's opaque type, and linking failed on deployment targets below the overload's availability.

Rule: the task lives in a private view modifier inside `FlowSwiftUI`, so the opaque type stays in this module. The public signature is unchanged.

## A collecting observer never deallocated

Trap: the collection task inside `ObservedStateFlow` captured the observer strongly.

Finding: before 2.2.0 the observer was never released while it was collecting, so `deinit` never ran and never cancelled the collection. An `isolated deinit` on the class also crashed the Swift 6.3 optimizer in release builds.

Rule: the task captures the source and a weak observer. A small helper owns the task and cancels it from that helper's `deinit`. Releasing the observer cancels collection.

## A wall-clock wait failed correct tests

Trap: tests decided success by sleeping, or by a timeout on the real clock.

Finding: the 2.2.0 suite work replaced those waits. On a loaded machine the executor backlog stretched a correct test past a fixed timeout. Polling flags and `Task.yield` loops also occupied the cooperative pool and starved other tests.

Rule: read a flow with `probing`, which suspends on the flow's own next event and has no deadline. Move time with `TestClock`. The 2.3.0 clock overloads of `test`, `TestScope.run`, `withThrowingTimeout`, and `waitUntil` expire only when that clock advances. The real-clock overloads stay, and they are deprecated.
