import Foundation
import FlowSharedModels

/// A scope that owns a set of long-running collection tasks, analogous to
/// Kotlin's `CoroutineScope`. Cancelling the scope cancels all tasks launched
/// in it. Safe to use as a property on a view controller, view model, or any
/// object whose lifetime should bound the collection tasks it launches.
///
/// ## Why FlowScope exists
///
/// Swift's structured concurrency (`TaskGroup`, `withTaskGroup`) is scoped to
/// function-call lifetimes, not object lifetimes. Long-running collection of
/// a flow tied to a view controller's lifetime needs a container that outlives
/// any single function call but still propagates cancellation cleanly.
/// `FlowScope` is that container.
///
/// ## Usage — UIKit integration
///
/// ```swift
/// final class NewsViewController: UIViewController {
///     private let viewModel: NewsViewModel
///     private let scope = FlowScope()
///
///     override func viewDidLoad() {
///         super.viewDidLoad()
///         viewModel.articles
///             .onEach { [weak self] articles in
///                 self?.render(articles)
///             }
///             .launch(in: scope)
///     }
///
///     // scope's deinit cancels all launched tasks automatically
/// }
/// ```
///
/// ## Lifetime note
///
/// A `FlowScope` retains every flow launched in it via the Task's captured
/// closure, until either the Task completes (at which point the Task is
/// automatically removed from the scope) or the scope is cancelled /
/// deinitialized. Long-lived scopes (e.g., on a singleton coordinator) will
/// keep flows alive until explicit cancellation. Pair scopes with clear
/// lifetime boundaries — typically a view controller, a view model, or an
/// explicit user session.
public final class FlowScope: @unchecked Sendable {
    internal let state: Mutex<State>

    internal struct State {
        var tasks: [UUID: Task<Void, Never>] = [:]
        var isCancelled: Bool = false
    }

    public init() {
        self.state = Mutex(State())
    }

    /// The number of tasks currently active in this scope. Exposed for
    /// testing and debugging; consumers should not use this for flow-control
    /// logic.
    public var activeTaskCount: Int {
        state.withLock { $0.tasks.count }
    }

    /// Launches `work` as a child task of this scope. The task is registered
    /// in the scope's task table and removes itself when it completes, so
    /// long-lived scopes do not accumulate completed tasks.
    ///
    /// If the scope has already been cancelled, the returned task is created
    /// in a cancelled state and never runs meaningful work.
    @discardableResult
    public func launch(
        priority: TaskPriority? = nil,
        _ work: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let id = UUID()

        let task = Task(priority: priority) { [weak self] in
            await work()
            self?.state.withLock { state in
                state.tasks.removeValue(forKey: id)
            }
        }

        state.withLock { state in
            guard !state.isCancelled else {
                task.cancel()
                return
            }
            state.tasks[id] = task
        }

        return task
    }

    /// Cancels all tasks launched in this scope and marks the scope as
    /// cancelled. Subsequent `launch` calls will immediately produce
    /// cancelled tasks. Idempotent.
    public func cancel() {
        state.withLock { state in
            state.isCancelled = true
            state.tasks.values.forEach { $0.cancel() }
            state.tasks.removeAll()
        }
    }

    deinit {
        state.withLock { state in
            state.isCancelled = true
            state.tasks.values.forEach { $0.cancel() }
            state.tasks.removeAll()
        }
    }
}
