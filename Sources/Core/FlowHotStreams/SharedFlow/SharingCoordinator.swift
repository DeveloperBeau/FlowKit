import Foundation
public import FlowSharedModels

public actor SharingCoordinator {
    private let strategy: SharingStrategy
    private let clock: any Clock<Duration>
    private let startClosure: @Sendable () -> Void
    private let stopClosure: @Sendable () -> Void
    private let resetReplayClosure: @Sendable () async -> Void

    private var isActive: Bool = false
    private var isUpstreamRunning: Bool = false
    private var subscriberCount: Int = 0
    private var pendingStopTask: Task<Void, Never>?
    private var pendingResetTask: Task<Void, Never>?
    // A reset in progress. A new subscriber waits for it before it can read
    // the replay, so it never sees the value being cleared.
    private var runningReset: Task<Void, Never>?

    public init(
        strategy: SharingStrategy,
        clock: any Clock<Duration>,
        start: @escaping @Sendable () -> Void,
        stop: @escaping @Sendable () -> Void,
        resetReplay: @escaping @Sendable () async -> Void = {}
    ) {
        self.strategy = strategy
        self.clock = clock
        self.startClosure = start
        self.stopClosure = stop
        self.resetReplayClosure = resetReplay
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
        pendingResetTask?.cancel()
        pendingResetTask = nil
        if isUpstreamRunning {
            stopUpstream()
        }
    }

    /// Records a new subscriber. Returns only after any replay reset already
    /// under way has finished, so the subscriber cannot read a stale replay.
    public func subscriberDidAppear() async {
        pendingStopTask?.cancel()
        pendingStopTask = nil
        pendingResetTask?.cancel()
        pendingResetTask = nil
        subscriberCount += 1

        if let runningReset { await runningReset.value }

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
        case .whileSubscribed(let stopTimeout, let replayExpiration):
            let strategyClock = clock
            if stopTimeout == .zero {
                if isUpstreamRunning { stopUpstream() }
            } else {
                pendingStopTask = Task { [weak self] in
                    try? await strategyClock.sleep(for: stopTimeout, tolerance: nil)
                    await self?.maybeFireDelayedStop()
                }
            }

            if replayExpiration == .zero {
                await resetReplay()
            } else {
                pendingResetTask = Task { [weak self] in
                    try? await strategyClock.sleep(for: replayExpiration, tolerance: nil)
                    await self?.maybeFireDelayedReset()
                }
            }

            if pendingStopTask != nil || pendingResetTask != nil {
                // Yield so the task bodies start and register their sleeps
                // before the caller can advance a test clock.
                await Task.yield()
            }
        }
    }

    private func maybeFireDelayedReset() async {
        guard pendingResetTask != nil, !Task.isCancelled else { return }
        guard subscriberCount == 0 else { return }
        pendingResetTask = nil
        await resetReplay()
    }

    /// Clears the replay. The reset runs as a task that `subscriberDidAppear`
    /// awaits, because the coordinator is reentrant across this suspension.
    private func resetReplay() async {
        let reset = Task { [resetReplayClosure] in await resetReplayClosure() }
        runningReset = reset
        await reset.value
        if runningReset == reset { runningReset = nil }
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
