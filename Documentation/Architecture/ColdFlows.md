# Cold flows

`Flow<Element>` and `ThrowingFlow<Element>` are cold streams. Creating one stores a body. The body runs when something collects, and each collector runs it again from the start. There is no shared execution and no replay.

`Element` is `Sendable`. The body and the collector action are `Sendable`. The body runs on the task that collects. The library does not hop to another actor or scheduler.

Choose `Flow` when the source cannot fail and `ThrowingFlow` when it can. There is no shared protocol and no type erasure between them. `mapThrowing` turns a `Flow` into a `ThrowingFlow`. `catch` on a `ThrowingFlow` handles the error and returns a `Flow`. The catalogue page [Flow vs ThrowingFlow](https://developerbeau.github.io/FlowKit/documentation/flow/flowvsthrowingflow) is the decision guide.

## Main types

| Type | File | Role |
|---|---|---|
| `Flow` | `Sources/Core/FlowCore/Flow/Flow.swift` | Cold stream that cannot fail |
| `ThrowingFlow` | `Sources/Core/FlowCore/ThrowingFlow/ThrowingFlow.swift` | Cold stream that can fail |
| `Collector` | `Sources/Core/FlowCore/Flow/Collector.swift` | Handle the body uses to `emit` |
| `ThrowingCollector` | `Sources/Core/FlowCore/ThrowingFlow/ThrowingCollector.swift` | Same handle, allowed to throw |
| `FlowScope` | `Sources/Core/FlowCore/Flow/FlowScope.swift` | Owns collection tasks for an object's lifetime |
| `ProducerScope` | `Sources/Core/FlowCore/Flow/ChannelFlow.swift` | Push handle for `channelFlow` and `callbackFlow` |
| `ChannelSendResult` | `Sources/Core/FlowCore/Flow/ChannelFlow.swift` | `.enqueued`, `.dropped`, or `.closed` |

`Collector.emit` calls the downstream action and suspends until that action returns. With no buffer, a slow collector slows the producer. `Collector` is a wrapper over `ThrowingCollector` whose action cannot throw.

Builders on `Flow` are `init(_:)`, `init(of:)`, a `Sequence` initializer, `empty`, `never`, and `Sequence.asFlow()`. `ThrowingFlow` has the same set except `never`, plus `asThrowingFlow()`. `Flow.never` suspends in a loop with `Task.sleep` so a cancelled task wakes it without a busy loop. That sleep is the exception recorded in [standards.md](../../standards.md).

## Channels

`Flow.channelFlow` and `Flow.callbackFlow` start a producer block per collector. The block receives a `ProducerScope`. `trySend` does not suspend and returns a `ChannelSendResult`. `send` suspends only when `onBufferOverflow` is `.suspend` and `bufferCapacity` is positive. Otherwise `send` matches `trySend`.

The defaults are `bufferCapacity: 64` and `onBufferOverflow: .dropOldest`. A capacity of zero or less is unbounded. Under `.suspend`, `trySend` cannot backpressure, so it buffers without a bound. `send` is what applies the bound, through `SendGate`.

The flow ends when the block calls `close()`, returns, or the collector is cancelled. `awaitClose` parks the block until then and runs its cleanup once. `callbackFlow` is `channelFlow` plus a debug assertion that the block parked on `awaitClose` or closed. A callback bridge that returns immediately would leave the callback writing into a finished channel.

## Cancellation and scope

`collect` returns when the body returns. Cancelling the collecting task is cooperative: the body sees it at the next suspension. [Cancellation](https://developerbeau.github.io/FlowKit/documentation/flow/cancellationsemantics) describes that chain.

`FlowScope` exists because a `TaskGroup` lives for a function call, and a view controller or view model lives longer. `launch` registers a task. The task removes itself when it finishes. `cancel()`, and `deinit`, cancel every task still in the table. A `launch` after `cancel` returns a task that is already cancelled.

`Flow.launch(in:)` and `ThrowingFlow.launch(in:)` collect inside the scope and drop the values. Side effects belong in `onEach` before `launch`. Errors from a throwing launch are swallowed. Handle them with `catch` first.

`FlowScope` retains a launched flow until the task finishes or the scope is cancelled. A scope stored on a long-lived object keeps that work alive until an explicit `cancel`.
