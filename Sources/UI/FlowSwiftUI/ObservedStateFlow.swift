#if canImport(SwiftUI) && canImport(Observation)
public import SwiftUI
public import Observation
internal import FlowCore
public import FlowHotStreams

/// Bridges a `StateFlow` into the `@Observable` world. Collects the flow
/// on the main actor and updates `value` whenever the flow emits. Used
/// internally by `@CollectedState`.
///
/// The collection task is held in a `CancellingTask`, whose own `deinit`
/// cancels it, so releasing the observer cancels the collection. This avoids
/// an `isolated deinit` on the class, which crashes the Swift 6.3 optimizer
/// in release builds.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
@Observable
@MainActor
public final class ObservedStateFlow<Element: Sendable & Equatable> {
    public private(set) var value: Element

    private let source: any StateFlow<Element>
    private let updatePolicy: UpdatePolicy

    @ObservationIgnored
    private var collectionTask: CancellingTask?

    /// Whether updates should be applied. `stop()` clears it on the main actor
    /// and `applyUpdate` also runs on the main actor and checks it, so a value
    /// that raced the task's cancellation can never mutate `value` after a stop.
    @ObservationIgnored
    private var isActive = false

    public enum UpdatePolicy: Sendable {
        case immediate
        case animated(Animation)
        case transaction(@Sendable () -> Transaction)
    }

    public init(
        _ source: any StateFlow<Element>,
        initialValue: Element,
        updatePolicy: UpdatePolicy = .immediate
    ) {
        self.source = source
        self.value = initialValue
        self.updatePolicy = updatePolicy
    }

    public func start() {
        guard collectionTask == nil else { return }
        isActive = true
        // Capture the source, not `self`: a strong `self` held across the
        // collection would keep the observer alive and its deinit unreachable.
        let source = source
        collectionTask = CancellingTask(Task { [weak self] in
            await source.asFlow().collect { [weak self] newValue in
                await self?.applyUpdate(newValue)
            }
        })
    }

    public func stop() {
        isActive = false
        collectionTask?.task.cancel()
        collectionTask = nil
    }

    private func applyUpdate(_ newValue: Element) {
        guard isActive, newValue != value else { return }
        switch updatePolicy {
        case .immediate:
            value = newValue
        case .animated(let animation):
            withAnimation(animation) { value = newValue }
        case .transaction(let factory):
            withTransaction(factory()) { value = newValue }
        }
    }
}

/// Cancels its task when released. Being a separate nonisolated class, its
/// `deinit` runs wherever the last reference drops, and `Task.cancel()` is
/// safe from any thread.
private final class CancellingTask: Sendable {
    let task: Task<Void, Never>

    init(_ task: Task<Void, Never>) {
        self.task = task
    }

    deinit {
        task.cancel()
    }
}
#endif
