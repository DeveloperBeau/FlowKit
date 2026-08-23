#if canImport(Darwin)
internal import Darwin
#elseif canImport(Bionic)
internal import Bionic
#elseif canImport(Glibc)
internal import Glibc
#else
#error("Unsupported platform: no C library providing a mutex primitive.")
#endif

/// A minimal mutex wrapper that protects a value of type `Value` and exposes
/// access through a closure-based `withLock` API. Shared across all FlowKit
/// targets via FlowSharedModels.
///
/// We roll our own wrapper rather than using `Synchronization.Mutex` because
/// the standard library version requires iOS 18 / macOS 15, and our platform
/// minimum is iOS 16 / macOS 13. On Darwin we use `os_unfair_lock_s`; on
/// Linux we use `pthread_mutex_t`. Both provide the same semantics for our
/// single-writer single-reader protection pattern.
///
/// ## Why a class, not a struct
///
/// The lock primitive has to live at one fixed address for its entire
/// lifetime — `os_unfair_lock` must never move, and `pthread_mutex_t` is
/// initialized in place. Taking `&` on a stored property doesn't promise
/// that address, so the lock is allocated once on the heap and every call
/// goes through that pointer. The class is what lets many tasks share the
/// one lock: it gives the pointer somewhere stable to live.
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
public final class Mutex<Value>: @unchecked Sendable {
    #if canImport(Darwin)
    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    #else
    private let lock: UnsafeMutablePointer<pthread_mutex_t>
    #endif

    private var storage: Value

    public init(_ value: Value) {
        self.storage = value
        self.lock = .allocate(capacity: 1)
        #if canImport(Darwin)
        lock.initialize(to: os_unfair_lock_s())
        #else
        lock.initialize(to: pthread_mutex_t())
        pthread_mutex_init(lock, nil)
        #endif
    }

    deinit {
        #if !canImport(Darwin)
        pthread_mutex_destroy(lock)
        #endif
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Executes `body` while holding the lock. The lock is released even if
    /// `body` throws. Returns whatever `body` returns.
    ///
    /// `sending` on the parameter and result matters when `Value` isn't
    /// `Sendable`: without it, a value handed out through the closure (or
    /// assigned into it) could cross a thread boundary with nothing
    /// checking that it was safe to share.
    @discardableResult
    public func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> sending R {
        #if canImport(Darwin)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        #else
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        #endif
        return try body(&storage)
    }
}
