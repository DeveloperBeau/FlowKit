# Changelog

All notable changes to FlowKit are documented here.

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

