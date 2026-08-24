#if canImport(Darwin)
internal import os
#elseif canImport(Bionic)
internal import Bionic
#elseif canImport(Glibc)
internal import Glibc
internal import Synchronization
#else
#error("Unsupported platform: no lock primitive available.")
#endif

/// A minimal mutex wrapper that protects a value of type `Value` and exposes
/// access through a closure-based `withLock` API. Shared across all FlowKit
/// targets via FlowSharedModels.
///
/// The standard library ships its own `Mutex`, but it's gated to iOS 18 /
/// macOS 15 on Darwin — the version symbol only exists on OS releases new
/// enough to carry it, because Apple's runtime is back-deployed and ABI
/// stable. Our floor is iOS 16 / macOS 13, so on Darwin we lean on
/// `OSAllocatedUnfairLock` instead, which covers that same floor. Linux has
/// no such back-deployment story — the Swift runtime ships inside the
/// binary rather than the OS — so the standard library's `Mutex` is
/// available there unconditionally at this toolchain, and we use it
/// directly rather than hand-rolling a lock. Android has no equivalent
/// platform-provided answer available in this SDK, so it keeps a hand-rolled
/// `pthread_mutex_t` wrapper.
///
/// `Value` must be `Sendable`. That's what makes the lock itself safe to
/// share across tasks unconditionally: nothing that comes out of `withLock`,
/// or goes into it, can be a value that was only safe to touch from one
/// place.
///
/// ## Why the lock needs help finding a stable address
///
/// A lock primitive like `os_unfair_lock` or `pthread_mutex_t` has to live
/// at one fixed memory address for its entire lifetime — it must never be
/// copied or moved once locked. Taking `&` on an ordinary stored property
/// doesn't promise you that address. `OSAllocatedUnfairLock` and the
/// standard library's `Mutex` both solve this internally, which is also why
/// they can hold `Value` directly instead of needing a separate stored
/// property next to the lock. Android has no such type available here, so
/// it still allocates the lock on the heap itself and refers to it through
/// a pointer for the same reason.
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
public final class Mutex<Value: Sendable>: @unchecked Sendable {
    #if canImport(Darwin)
    private let lock: OSAllocatedUnfairLock<Value>
    #elseif canImport(Glibc)
    private let lock: Synchronization.Mutex<Value>
    #else
    private let lock: UnsafeMutablePointer<pthread_mutex_t>
    private var storage: Value
    #endif

    public init(_ value: Value) {
        #if canImport(Darwin)
        self.lock = OSAllocatedUnfairLock(initialState: value)
        #elseif canImport(Glibc)
        self.lock = Synchronization.Mutex(value)
        #else
        self.storage = value
        self.lock = .allocate(capacity: 1)
        lock.initialize(to: pthread_mutex_t())
        pthread_mutex_init(lock, nil)
        #endif
    }

    #if !canImport(Darwin) && !canImport(Glibc)
    deinit {
        pthread_mutex_destroy(lock)
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    #endif

    /// Executes `body` while holding the lock. The lock is released even if
    /// `body` throws. Returns whatever `body` returns.
    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        #if canImport(Darwin)
        return try lock.withLockUnchecked(body)
        #elseif canImport(Glibc)
        return try lock.withLock { value in try body(&value) }
        #else
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        return try body(&storage)
        #endif
    }
}
