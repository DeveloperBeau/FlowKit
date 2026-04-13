import Foundation
public import FlowSharedModels

public actor SharingCoordinator {
    private let strategy: SharingStrategy
    private let clock: any Clock<Duration>
    private let startClosure: @Sendable () -> Void
    private let stopClosure: @Sendable () -> Void

    private var isActive: Bool = false
    private var isUpstreamRunning: Bool = false
    private var subscriberCount: Int = 0
    private var pendingStopTask: Task<Void, Never>?

    public init(
        strategy: SharingStrategy,
        clock: any Clock<Duration>,
        start: @escaping @Sendable () -> Void,
        stop: @escaping @Sendable () -> Void
    ) {
        self.strategy = strategy
        self.clock = clock
        self.startClosure = start
        self.stopClosure = stop
    }

    public func activate() {
        isActive = true
        if case .eager = strategy {
            startUpstream()
        }
    }

    public func deactivate() {
        isActive = false
        pendingStopTask?.cancel()
        pendingStopTask = nil
        if isUpstreamRunning {
            stopUpstream()
        }
    }

    public func subscriberDidAppear() {
        pendingStopTask?.cancel()
        pendingStopTask = nil
        subscriberCount += 1

        if !isUpstreamRunning && isActive {
            switch strategy {
            case .eager, .lazy, .whileSubscribed:
                startUpstream()
            }
        }
    }

    public func subscriberDidDisappear() async {
        subscriberCount -= 1
        precondition(subscriberCount >= 0, "subscriber count went negative")

        guard subscriberCount == 0 else { return }

        switch strategy {
        case .eager, .lazy:
            return
        case .whileSubscribed(let stopTimeout, _):
            if stopTimeout == .zero {
                if isUpstreamRunning { stopUpstream() }
                return
            }

            let strategyClock = clock
            let task = Task { [weak self] in
                try? await strategyClock.sleep(for: stopTimeout, tolerance: nil)
                await self?.maybeFireDelayedStop()
            }
            pendingStopTask = task
            // Yield so the task body starts and registers its sleep before
            // the caller can advance a test clock.
            await Task.yield()
        }
    }

    private func maybeFireDelayedStop() {
        guard pendingStopTask != nil, !Task.isCancelled else { return }
        guard subscriberCount == 0 else { return }

        if isUpstreamRunning {
            stopUpstream()
        }
        pendingStopTask = nil
    }

    private func startUpstream() {
        guard !isUpstreamRunning else { return }
        isUpstreamRunning = true
        startClosure()
    }

    private func stopUpstream() {
        guard isUpstreamRunning else { return }
        isUpstreamRunning = false
        stopClosure()
    }
}
