#if canImport(Darwin)
internal import Darwin
#else
internal import Glibc
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
/// `Mutex` is a reference type because the underlying lock must have a stable
/// memory address. `os_unfair_lock` must not be moved, and `pthread_mutex_t`
/// is initialized in place. Wrapping in a class gives us this stability.
public final class Mutex<Value>: @unchecked Sendable {
    #if canImport(Darwin)
    private var lock = os_unfair_lock_s()
    #else
    private var lock = pthread_mutex_t()
    #endif

    private var storage: Value

    public init(_ value: Value) {
        self.storage = value
        #if !canImport(Darwin)
        pthread_mutex_init(&lock, nil)
        #endif
    }

    deinit {
        #if !canImport(Darwin)
        pthread_mutex_destroy(&lock)
        #endif
    }

    /// Executes `body` while holding the lock. The lock is released even if
    /// `body` throws. Returns whatever `body` returns.
    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        #if canImport(Darwin)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        #else
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        #endif
        return try body(&storage)
    }
}
