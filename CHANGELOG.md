# Changelog

All notable changes to FlowKit are documented here.

## 2.2.0 — 2026-10-05

### Added

- `FlowReader` and `Flow.probing(_:)` / `ThrowingFlow.probing(_:)` in `FlowTesting`: read a
  flow with no deadline. `awaitValue()`, `expectValue(_:)`, `expectError(_:matching:)`,
  `expectCompletion()` and `cancelAndIgnoreRemaining()` suspend on the flow's own next
  emission, completion or failure, so a loaded machine cannot fail a correct test. A flow that
  ends before an expected value records a failure and every later read fails the same way.
  `expectNextValue(_:)` replaces `expectNoValue(within:)` for clock-free "nothing arrived
  before this" checks. A producer that stays open and never emits again cannot be told from a
  slow one without a clock; use `test(timeout:_:)` when that bound matters. Existing testing
  APIs are unchanged.

### Fixed

- `View.collecting` no longer fails to link in release builds. It returned SwiftUI's `.task`
  directly, which with current SDKs resolves to the newer `task(name:priority:file:line:_:)`
  overload; a release build then referenced that overload's opaque type descriptor from the
  client module, and linking failed on deployment targets below its availability. The task now
  lives in a private view modifier. The public signature is unchanged.
- Building `FlowSwiftUI` in release with Swift 6.3 no longer crashes the compiler (signal 11
  in the inliner, on `ObservedStateFlow`'s `isolated deinit`).
- A collecting `ObservedStateFlow` can now be deallocated. The collection task captured the
  observer strongly, so it was never released while collecting and its deinit never cancelled
  the collection. Releasing the observer now cancels collection.

### Internal

- The test suite no longer depends on wall-clock deadlines: flows are read through `probing`,
  and callbacks and state through signals and recorders, so a stalled test process cannot fail a
  correct test.
- CI tests every target in the release configuration on macOS, including the UI targets.

## 2.1.0 — 2026-09-22

### Changed

- Reorganized `Sources/` and `Tests/` from a flat list of target directories into
  layer-based groups — `Shared/`, `Core/`, `UI/`, `Testing/` — mirroring the `Flow`,
  `FlowTesting`, and `FlowUI` products, and split the largest targets' flat file lists
  into subfolders by responsibility (e.g. `FlowCore` into `Flow`/`ThrowingFlow`,
  `FlowOperatorsTests` into per-operator-category folders). This is a pure internal
  reorganization: target names, the public product surface, and every API are unchanged.
- Updated pinned dependencies: `swift-async-algorithms` 1.1.3 → 1.1.5, `swift-docc-plugin`
  1.4.6 → 1.5.0, `swift-crypto` 4.5.1 → 5.0.0. The crypto major bump is additive and
  internal-visibility cleanup on Apple's side; nothing FlowKit calls was removed, and
  `swift-crypto` is scoped to a test target, so it never reaches consumers of `Flow`,
  `FlowTesting`, or `FlowUI`.

## 2.0.0 — 2026-08-25

### Breaking

- `Mutex<Value>` now requires `Value: Sendable`. Creating a `Mutex` around a type that
  isn't `Sendable` no longer compiles. Every payload used internally already satisfied
  this, but a downstream consumer holding `Mutex<SomeNonSendableType>` will need to make
  that type `Sendable` (or stop storing it in a `Mutex`) before updating.
- `Mutex.withLock`'s closure must now return a `Sendable` result. A closure that returns
  a non-`Sendable` value no longer compiles. Previously this compiled and let a
  non-`Sendable` value leave the lock's protection with nothing checking it was safe to
  share elsewhere.

Both changes are compile-time only, and there is no behavior change for code that already
satisfied them, which is every call site in this package. They only affect consumers
holding a non-`Sendable` payload in a `Mutex`, or returning one from a `withLock`
closure.

#### Upgrading from 1.x

Most consumers need no changes: if your code compiles against 1.2.2 without storing a
non-`Sendable` value in a `Mutex`, it compiles here unchanged. If it doesn't, the compiler
points at the exact declaration — make the stored type `Sendable`, or move it out of the
`Mutex`. There is no runtime behaviour change to account for either way.

### Added

- The `Flow` and `FlowTesting` products cross-compile for Android (`aarch64` and `x86_64`,
  API 28) with the Swift SDK for Android. Every pull request is gated on that build.
- A nightly, non-blocking job runs the eight non-UI test suites on an x86_64 Android
  emulator. It is the only place FlowKit is executed on Android, and it is not a required
  check — the Android build is guaranteed, Android runtime behaviour is monitored.
  `FlowUI` remains Apple-only.

### Changed

- `Mutex`'s locking implementation changed on both supported platforms. On Darwin it
  now uses `OSAllocatedUnfairLock` instead of a hand-rolled `os_unfair_lock` wrapper.
  Everywhere else it now uses the standard library's `Synchronization.Mutex` instead of
  a hand-rolled `pthread_mutex_t` wrapper. `Mutex`'s public API and behavior are
  unaffected; this is an internal implementation change riding along with the
  constraints above.

