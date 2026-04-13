# Cancellation Semantics

How cancellation flows from ``FlowCore/FlowScope`` through Swift Tasks into flow bodies — and what goes wrong when you bypass the chain.

## Overview

FlowKit cancellation is built on Swift structured concurrency. Understanding the chain — scope → task → flow body — lets you reason confidently about cleanup, prevents resource leaks, and avoids the most common pitfall: an orphaned `Task` inside a collector that keeps running after the owning scope is cancelled.

## Structured concurrency in one paragraph

Swift structured concurrency guarantees that child tasks cannot outlive their parent. When a parent task is cancelled, cancellation propagates to every child in its tree. `async`/`await` suspension points check for cancellation cooperatively: `Task.isCancelled` returns `true` and functions marked `throws` raise `CancellationError`. This makes cancellation observable rather than forceful — a flow body cleans up before it stops.

## FlowScope

``FlowCore/FlowScope`` is the object-lifetime equivalent of a `TaskGroup`. It holds a dictionary of running `Task` handles and cancels them all when its `cancel()` method is called or when it is deallocated.

```swift
// Every task launched in the scope is tracked.
let scope = FlowScope()

locationManager.updates
    .onEach { [weak self] location in self?.updateMap(location) }
    .launch(in: scope)

chatRepository.messages(for: roomID)
    .onEach { [weak self] message in self?.appendMessage(message) }
    .launch(in: scope)

// Cancelling the scope cancels both tasks atomically.
scope.cancel()
```

After `cancel()`, any subsequent `launch` calls immediately produce cancelled tasks — the scope never runs new work once marked cancelled.

## How flow bodies observe cancellation

A ``FlowCore/Flow`` body is an `async` closure. When its owning task is cancelled, the next suspension point inside the body sees `Task.isCancelled == true`. Operators that use `Task` internally — `flatMapLatest`, `debounce`, `buffer(.suspend)` — all check cancellation and exit cleanly at their natural suspension points.

For flows that wrap external resources (e.g., a WebSocket connection), use `withTaskCancellationHandler` to schedule synchronous cleanup before the cooperative check can run:

```swift
// Real-time chat: cancel the WebSocket read loop immediately on scope cancel.
let messages: Flow<ChatMessage> = Flow { collector in
    let socket = try! await ChatSocket.connect(to: roomURL)
    await withTaskCancellationHandler {
        for await frame in socket.frames {
            guard let message = ChatMessage(frame) else { continue }
            await collector.emit(message)
        }
    } onCancel: {
        socket.disconnect()   // synchronous, called immediately on cancellation
    }
}
```

The `onCancel` handler fires synchronously on whatever thread calls `task.cancel()`. Keep it fast and free of Swift concurrency (`await`), since it runs outside the cooperative scheduler.

## UIKit: flowScope cancels on deinit

`UIViewController.flowScope` is a ``FlowCore/FlowScope`` stored as an associated object on the view controller. Because associated objects are released when the owning object deallocates, the scope's `deinit` cancels all tasks the moment the view controller is released from memory.

```swift
final class ChatViewController: UIViewController {
    private let viewModel: ChatViewModel

    override func viewDidLoad() {
        super.viewDidLoad()

        // Collection is tied to the VC's lifetime — no manual cancel needed.
        collect(viewModel.messages) { [weak self] messages in
            self?.renderMessages(messages)
        }

        viewModel.connectionStatus
            .asFlow()
            .onEach { [weak self] status in self?.updateStatusBanner(status) }
            .launch(in: flowScope)
    }
    // When this VC is popped and released, flowScope deallocates,
    // cancelling both the messages and connection-status tasks.
}
```

No `deinit` override, no manual `cancel()` call. The scope handles it.

## SwiftUI: @CollectedState cancels on view disappear

``FlowSwiftUI/CollectedState`` is a `DynamicProperty` that starts collection in `update()` — which SwiftUI calls when the view appears — and cancels when the view is removed from the hierarchy. You get automatic flow lifetime tied to view lifetime with no manual plumbing:

```swift
struct SessionBanner: View {
    // Starts collecting when the view appears; cancels when it disappears.
    @CollectedState(SessionManager.shared.sessionState)
    var session: SessionState = .signedOut

    var body: some View {
        switch session {
        case .signedIn(let user): Text("Signed in as \(user.displayName)")
        case .signingIn: ProgressView("Authenticating…")
        case .signedOut: EmptyView()
        case .error(let message): Text(message).foregroundStyle(.red)
        }
    }
}
```

If the view is pushed off-screen and the `StateFlow` uses `.whileSubscribed(stopTimeout: .seconds(5))`, the upstream stops after the timeout — saving CPU, network, and battery for flows that aren't being observed.

## The orphaned Task pitfall

The most common mistake is launching an unstructured `Task` inside a collector body:

```swift
// BAD: the inner Task escapes the scope's cancellation tree.
viewModel.feedItems
    .onEach { items in
        Task {                          // ← unstructured, NOT owned by scope
            let thumbnails = await imageCache.prefetch(items)
            updateThumbnailGrid(thumbnails)
        }
    }
    .launch(in: viewScope)
```

When `viewScope` is cancelled, the `onEach` task stops — but the inner `Task` keeps running. The prefetch continues, `updateThumbnailGrid` is called on a deallocated view controller, and nothing cleans up the image cache work.

The fix is to keep work inside the structured chain:

```swift
// GOOD: use flatMap to keep the inner work in the cancellation tree.
viewModel.feedItems
    .flatMap { items in
        Flow { collector in
            let thumbnails = await imageCache.prefetch(items)
            await collector.emit(thumbnails)
        }
    }
    .onEach { updateThumbnailGrid($0) }
    .launch(in: viewScope)
```

Now when `viewScope` is cancelled, `flatMap`'s inner `Flow` body is also cancelled. No orphan.

## Related concepts

- <doc:LifecycleAwareCollection> — binding scopes to UIKit, AppKit, and SwiftUI lifetimes
- <doc:HotVsColdStreams> — why hot streams need explicit scope management
