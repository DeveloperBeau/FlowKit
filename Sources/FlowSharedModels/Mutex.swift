// This isn't really asking "is this an Apple platform." It's asking "does
// the OS ship its own stdlib that I have to stay compatible with." Darwin
// back-deploys an ABI-stable standard library onto old OS releases, so
// `Synchronization.Mutex` genuinely doesn't exist below iOS 18 / macOS 15,
// and `os_unfair_lock` is what's available at our iOS 16 floor instead.
// Everywhere else, the standard library ships inside the app binary rather
// than the OS, so `Mutex` is always there at this toolchain.
//
// `canImport(Synchronization)` looks like the more honest check here, but
// don't use it: the module is present at every deployment target, including
// ones below the `Mutex` availability gate, so it can't tell you whether
// `Mutex` itself is usable. It would compile on this line and then fail on
// the first real use of `Mutex` further down.
#if canImport(Darwin)
internal import os
#else
internal import Synchronization
#endif

/// A minimal mutex wrapper that protects a value of type `Value` and exposes
/// access through a closure-based `withLock` API. Shared across all FlowKit
/// targets via FlowSharedModels.
///
/// The standard library ships its own `Mutex`, but it's gated to iOS 18 /
/// macOS 15 on Darwin, below our iOS 16 / macOS 13 floor, so on Darwin we
/// lean on `OSAllocatedUnfairLock` instead, which covers that same floor.
/// Everywhere else, the standard library's `Mutex` is available
/// unconditionally at this toolchain, so we use it directly.
///
/// `Value` must be `Sendable`, and so must whatever `withLock`'s closure
/// returns. Together those two constraints are what make the lock safe to
/// share across tasks unconditionally: nothing that goes into it, and
/// nothing that comes out of it, can be a value that was only safe to touch
/// from one place.
///
/// ## Why the lock needs help finding a stable address
///
/// A lock primitive has to live at one fixed memory address for its entire
/// lifetime — it must never be copied or moved once locked. Taking `&` on
/// an ordinary stored property doesn't promise you that address.
/// `OSAllocatedUnfairLock` and the standard library's `Mutex` both solve
/// this internally, which is also why they can hold `Value` directly
/// instead of needing a separate stored property next to the lock.
///
/// ## Re-entrancy
///
/// This lock is not recursive. Calling `withLock` again on the same
/// instance from inside a `withLock` closure deadlocks: the inner call
/// waits for the outer one to release, and the outer one is waiting on you.
///
/// ## Why the closure is synchronous
///
/// `body` cannot `await`, so the lock can never be held across a
/// suspension point. That's what makes `withLock` safe to call from async
/// code without worrying about starving other tasks on the same executor.
public final class Mutex<Value: Sendable>: Sendable {
    #if canImport(Darwin)
    private let lock: OSAllocatedUnfairLock<Value>
    #else
    private let lock: Synchronization.Mutex<Value>
    #endif

    public init(_ value: Value) {
        #if canImport(Darwin)
        self.lock = OSAllocatedUnfairLock(initialState: value)
        #else
        self.lock = Synchronization.Mutex(value)
        #endif
    }

    /// Executes `body` while holding the lock. The lock is released even if
    /// `body` throws, and a mutation `body` makes before throwing is kept:
    /// Swift commits `inout` writes on the way out either way, so a throw
    /// doesn't roll anything back. Returns whatever `body` returns.
    ///
    /// `R` must be `Sendable` for the same reason `Value` is: whatever comes
    /// out of the closure is about to leave the lock's protection and go
    /// wherever the caller takes it, so it has to already be safe to share.
    @discardableResult
    public func withLock<R: Sendable>(_ body: (inout Value) throws -> R) rethrows -> R {
        #if canImport(Darwin)
        // OSAllocatedUnfairLock.withLock (the checked variant) also requires
        // body itself to be @Sendable, which ours isn't: body's captured
        // context is whatever local, non-Sendable state the caller closed
        // over, and that's the normal, expected shape for this API. R being
        // Sendable is enforced above, on our own signature, so
        // withLockUnchecked isn't reopening the hole this pass closed, it's
        // just the one entry point that accepts a plain closure.
        return try lock.withLockUnchecked(body)
        #else
        return try lock.withLock { value in try body(&value) }
        #endif
    }
}
