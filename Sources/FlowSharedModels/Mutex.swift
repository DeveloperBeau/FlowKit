#if canImport(Darwin)
internal import os
#elseif canImport(Bionic)
internal import Bionic
#elseif canImport(Glibc)
internal import Glibc
#else
#error("Unsupported platform: no lock primitive available.")
#endif

/// A minimal mutex wrapper that protects a value of type `Value` and exposes
/// access through a closure-based `withLock` API. Shared across all FlowKit
/// targets via FlowSharedModels.
///
/// We roll our own wrapper rather than using `Synchronization.Mutex` because
/// the standard library version requires iOS 18 / macOS 15, and our platform
/// minimum is iOS 16 / macOS 13. On Darwin, `OSAllocatedUnfairLock` covers
/// that same floor and already solves the storage problem below, so we lean
/// on it there; on Linux we still roll our own `pthread_mutex_t` wrapper.
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
/// doesn't promise you that address. On Linux we still allocate the lock on
/// the heap ourselves and refer to it through a pointer for exactly that
/// reason. On Darwin, `OSAllocatedUnfairLock` handles this internally, which
/// is also why it can hold `Value` directly instead of needing a separate
/// stored property next to the lock.
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
    #else
    private let lock: UnsafeMutablePointer<pthread_mutex_t>
    private var storage: Value
    #endif

    public init(_ value: Value) {
        #if canImport(Darwin)
        self.lock = OSAllocatedUnfairLock(initialState: value)
        #else
        self.storage = value
        self.lock = .allocate(capacity: 1)
        lock.initialize(to: pthread_mutex_t())
        pthread_mutex_init(lock, nil)
        #endif
    }

    #if !canImport(Darwin)
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
        #else
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        return try body(&storage)
        #endif
    }
}
