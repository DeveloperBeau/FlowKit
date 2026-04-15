public import FlowCore
import FlowSharedModels
import Foundation

// MARK: - debounce

extension Flow {
    /// Waits for `duration` of silence (no new upstream emissions) before
    /// emitting the most recent value. Resets the timer on each new value.
    ///
    /// ## Example: debounced search
    ///
    /// ```swift
    /// let debouncedQuery: Flow<String> = searchTextField
    ///     .debounce(for: .milliseconds(300))
    /// ```
    public func debounce(
        for duration: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let sm = DebounceStateMachine<Element, _>(duration: duration, clock: clock)
            await withTaskGroup(of: Void.self) { group in
                // Clock task: preemptively suspends, waiting for a deadline.
                // When elementArrived() is called, it SYNCHRONOUSLY resumes
                // this task with the deadline computed at arrival time. This
                // guarantees clock.sleep(until:) uses the correct deadline
                // even if the task runs after clock.advance() has been called.
                group.addTask {
                    while true {
                        guard let deadline = await sm.waitForDeadline() else { return }
                        try? await clock.sleep(until: deadline, tolerance: nil)
                        sm.clockFired()
                        // Restart: wait for next deadline
                    }
                }

                // Output task: waits for values to emit downstream
                group.addTask {
                    while let value = await sm.waitForOutput() {
                        await downstream.emit(value)
                    }
                }

                // Upstream task: forwards values to state machine
                group.addTask {
                    await self.collect { value in
                        await sm.elementArrived(value, clock: clock)
                    }
                    sm.finished()
                }

                await group.waitForAll()
            }
        }
    }
}

extension ThrowingFlow {
    /// Debounce variant for throwing flows.
    public func debounce(
        for duration: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let sm = DebounceStateMachine<Element, _>(duration: duration, clock: clock)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while true {
                        guard let deadline = await sm.waitForDeadline() else { return }
                        try? await clock.sleep(until: deadline, tolerance: nil)
                        sm.clockFired()
                    }
                }
                group.addTask {
                    while let value = await sm.waitForOutput() {
                        try await downstream.emit(value)
                    }
                }
                group.addTask {
                    defer { sm.finished() }
                    try await self.collect { value in
                        await sm.elementArrived(value, clock: clock)
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

/// State machine for the debounce operator.
///
/// Uses a lock for synchronous coordination between the upstream collect
/// callback and the clock task. When `elementArrived` is called (from the
/// collect callback), it immediately resumes the clock task's continuation
/// with the deadline computed at the moment of arrival. This ensures
/// `clock.sleep(until: deadline)` is called in the correct cooperative turn
/// and that the deadline is correct even if the task runs after the clock
/// has been advanced.
private final class DebounceStateMachine<Element: Sendable, C: Clock<Duration>>: @unchecked Sendable
where C.Instant: Sendable {
    private let lock = NSLock()
    private let duration: Duration
    private var pending: Element? = nil
    private var clockWaiter: CheckedContinuation<C.Instant?, Never>? = nil
    private var outputWaiter: CheckedContinuation<Element?, Never>? = nil
    private var done = false

    init(duration: Duration, clock: C) {
        self.duration = duration
    }

    /// Called from the upstream collect callback. Computes the deadline at
    /// arrival time and immediately resumes the clock task if it is waiting.
    /// Yields after resuming so the clock task can call `clock.sleep` before
    /// control returns to the test's `clock.advance`.
    func elementArrived(_ value: Element, clock: C) async {
        let deadline = clock.now.advanced(by: duration)
        let waiter: CheckedContinuation<C.Instant?, Never>? = lock.withLock {
            pending = value
            let w = clockWaiter
            clockWaiter = nil
            return w
        }
        waiter?.resume(returning: deadline)
        // Yield to allow the clock task to wake up and call clock.sleep(until:)
        // before the test calls clock.advance(). This ensures the deadline is
        // registered with the TestClock in the correct cooperative turn.
        await Task.yield()
    }

    /// Called after upstream completes.
    func finished() {
        let (cw, ow): (CheckedContinuation<C.Instant?, Never>?, CheckedContinuation<Element?, Never>?) = lock.withLock {
            done = true
            let c = clockWaiter; let o = outputWaiter
            clockWaiter = nil; outputWaiter = nil
            return (c, o)
        }
        cw?.resume(returning: nil)
        ow?.resume(returning: nil)
    }

    /// Clock task suspends here waiting for the next deadline.
    func waitForDeadline() async -> C.Instant? {
        let earlyResult: C.Instant?? = lock.withLock {
            if done || Task.isCancelled { return .some(nil) }
            return nil  // need to suspend
        }
        if let result = earlyResult { return result }
        return await withCheckedContinuation { cont in
            lock.withLock {
                if done || Task.isCancelled {
                    cont.resume(returning: nil)
                } else {
                    clockWaiter = cont
                }
            }
        }
    }

    /// Called by the clock task after `clock.sleep` finishes.
    /// Moves the pending value to the output waiter.
    func clockFired() {
        let (value, waiter): (Element?, CheckedContinuation<Element?, Never>?) = lock.withLock {
            guard let v = pending else { return (nil, nil) }
            pending = nil
            let w = outputWaiter
            outputWaiter = nil
            return (v, w)
        }
        if let value, let waiter {
            waiter.resume(returning: value)
        }
    }

    /// Output task suspends here waiting for a value to emit.
    func waitForOutput() async -> Element? {
        let earlyResult: Element?? = lock.withLock {
            if done || Task.isCancelled { return .some(nil) }
            return nil  // need to suspend
        }
        if let result = earlyResult { return result }
        return await withCheckedContinuation { cont in
            lock.withLock {
                if done || Task.isCancelled {
                    cont.resume(returning: nil)
                } else {
                    outputWaiter = cont
                }
            }
        }
    }
}

// MARK: - throttle

extension Flow {
    /// Emits at most one value per `duration` interval. When `latest` is
    /// `true`, emits the most recent value at each interval boundary.
    /// When `false`, emits the first value received in each interval.
    ///
    /// ## Example: throttled scroll position
    ///
    /// ```swift
    /// let throttledScroll: Flow<CGFloat> = scrollOffset
    ///     .throttle(for: .milliseconds(100))
    /// ```
    public func throttle(
        for duration: Duration,
        latest: Bool = true,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let state = ThrottleState<Element>(
                duration: duration, latest: latest, clock: clock
            )
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.collect { value in
                        await state.receive(value)
                    }
                    await state.flush()
                }
                group.addTask {
                    for await value in state.stream {
                        await downstream.emit(value)
                    }
                }
                await group.waitForAll()
            }
        }
    }
}

extension ThrowingFlow {
    /// Throttle variant for throwing flows. Errors propagate downstream
    /// immediately, cancelling any pending timer window.
    public func throttle(
        for duration: Duration,
        latest: Bool = true,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let state = ThrottleState<Element>(
                duration: duration, latest: latest, clock: clock
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        try await self.collect { value in
                            await state.receive(value)
                        }
                    } catch {
                        await state.flush()
                        throw error
                    }
                    await state.flush()
                }
                group.addTask {
                    for await value in state.stream {
                        try await downstream.emit(value)
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

private actor ThrottleState<Element: Sendable> {
    private let duration: Duration
    private let latest: Bool
    private let clock: any Clock<Duration>
    private var firstValue: Element?
    private var latestValue: Element?
    private var windowOpen: Bool = true
    private var timerTask: Task<Void, Never>?

    let (stream, continuation): (AsyncStream<Element>, AsyncStream<Element>.Continuation)

    init(duration: Duration, latest: Bool, clock: some Clock<Duration>) {
        self.duration = duration
        self.latest = latest
        self.clock = clock
        (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func receive(_ value: Element) {
        if windowOpen {
            // First value in the window. Emit via stream and start timer.
            windowOpen = false
            firstValue = nil
            latestValue = nil
            continuation.yield(value)
            timerTask?.cancel()
            let cap = continuation
            timerTask = Task { [duration, clock] in
                try? await clock.sleep(for: duration, tolerance: nil)
                self.windowExpired(into: cap)
            }
        } else {
            if firstValue == nil { firstValue = value }
            latestValue = value
        }
    }

    private func windowExpired(into cap: AsyncStream<Element>.Continuation) {
        guard !Task.isCancelled else { return }
        let valueToEmit = latest ? latestValue : firstValue
        firstValue = nil
        latestValue = nil
        windowOpen = true
        if let value = valueToEmit {
            cap.yield(value)
        }
    }

    func flush() {
        timerTask?.cancel()
        continuation.finish()
    }
}

// MARK: - removeDuplicates

extension Flow where Element: Equatable {
    /// Drops consecutive duplicate values. Only emits when the value
    /// changes compared to the previous emission.
    ///
    /// ## Example: suppress duplicate search queries
    ///
    /// ```swift
    /// let uniqueQueries: Flow<String> = searchTextField
    ///     .removeDuplicates()
    /// ```
    public func removeDuplicates() -> Flow<Element> {
        removeDuplicates(by: ==)
    }
}

extension Flow {
    /// Drops consecutive values where `predicate` returns `true`,
    /// comparing each new value to the previously-emitted one.
    public func removeDuplicates(
        by predicate: @escaping @Sendable (Element, Element) -> Bool
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let state = RemoveDuplicatesState<Element>()
            await self.collect { value in
                let shouldEmit = await state.shouldEmit(value, predicate: predicate)
                if shouldEmit {
                    await downstream.emit(value)
                }
            }
        }
    }
}

extension ThrowingFlow where Element: Equatable {
    /// Drops consecutive duplicate values from a throwing flow.
    public func removeDuplicates() -> ThrowingFlow<Element> {
        removeDuplicates(by: ==)
    }
}

extension ThrowingFlow {
    /// Drops consecutive values where `predicate` returns `true` from a
    /// throwing flow. Errors propagate downstream immediately.
    public func removeDuplicates(
        by predicate: @escaping @Sendable (Element, Element) -> Bool
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let state = RemoveDuplicatesState<Element>()
            try await self.collect { value in
                let shouldEmit = await state.shouldEmit(value, predicate: predicate)
                if shouldEmit {
                    try await downstream.emit(value)
                }
            }
        }
    }
}

private actor RemoveDuplicatesState<Element: Sendable> {
    private var previous: Element?

    func shouldEmit(_ value: Element, predicate: (Element, Element) -> Bool) -> Bool {
        defer { previous = value }
        guard let prev = previous else { return true }
        return !predicate(prev, value)
    }
}

// MARK: - sample

extension Flow {
    /// Emits the most recent upstream value at fixed time intervals. If no
    /// value arrived since the last sample, the interval is skipped.
    ///
    /// ## Example: periodic position updates
    ///
    /// ```swift
    /// let sampledLocation: Flow<CLLocation> = locationUpdates
    ///     .sample(every: .seconds(1))
    /// ```
    public func sample(
        every interval: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> Flow<Element> {
        Flow<Element> { downstream in
            let state = SampleState<Element>()
            await withTaskGroup(of: Void.self) { group in
                // Collector task: stores latest value
                group.addTask {
                    await self.collect { value in
                        state.store(value)
                    }
                    state.markCompleted()
                }

                // Timer task: samples at intervals
                group.addTask {
                    while !Task.isCancelled {
                        try? await clock.sleep(for: interval, tolerance: nil)
                        if Task.isCancelled { break }
                        // Yield to let the collect task process any buffered
                        // upstream values before we sample the latest.
                        await Task.yield()
                        if let value = state.take() {
                            await downstream.emit(value)
                        }
                        if state.isCompleted { break }
                    }
                }
            }
        }
    }
}

extension ThrowingFlow {
    /// Sample variant for throwing flows. Errors propagate downstream
    /// immediately when the upstream throws; any pending sample is dropped.
    public func sample(
        every interval: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> ThrowingFlow<Element> {
        ThrowingFlow<Element> { downstream in
            let state = ThrowingSampleState<Element>()
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Upstream task: stores values; signals stop on completion or error.
                group.addTask {
                    do {
                        try await self.collect { value in
                            state.store(value)
                        }
                        state.signalStop()
                    } catch {
                        state.signalStop()
                        throw error
                    }
                }
                // Timer task: samples at intervals; stops when upstream signals done.
                group.addTask {
                    while !Task.isCancelled {
                        // Sleep interruptibly: the continuation is resumed either by
                        // the clock advancing OR by signalStop() from the upstream task.
                        await state.sleepOrStop(for: interval, clock: clock)
                        if Task.isCancelled || state.isStopped { break }
                        if let value = state.take() {
                            try await downstream.emit(value)
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

private final class SampleState<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Element?
    private var _isCompleted = false

    var isCompleted: Bool {
        lock.withLock { _isCompleted }
    }

    func store(_ value: Element) {
        lock.withLock { latest = value }
    }

    func take() -> Element? {
        lock.withLock {
            let value = latest
            latest = nil
            return value
        }
    }

    func markCompleted() {
        lock.withLock { _isCompleted = true }
    }
}

/// State for ThrowingFlow.sample that supports interrupting the timer sleep
/// when the upstream completes or fails.
private final class ThrowingSampleState<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Element?
    private var _isStopped = false
    private var sleepWaiter: CheckedContinuation<Void, Never>?

    var isStopped: Bool {
        lock.withLock { _isStopped }
    }

    func store(_ value: Element) {
        lock.withLock { latest = value }
    }

    func take() -> Element? {
        lock.withLock {
            let value = latest
            latest = nil
            return value
        }
    }

    /// Called by the upstream task (on both normal and error completion).
    /// Resumes any in-progress sleep so the timer task can exit promptly.
    func signalStop() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            _isStopped = true
            let w = sleepWaiter
            sleepWaiter = nil
            return w
        }
        waiter?.resume()
    }

    /// Sleeps for `interval` on `clock`, but returns early if `signalStop()`
    /// is called before the interval elapses. Combines a real clock sleep
    /// with a stop-signal in a child task group so both race concurrently.
    func sleepOrStop(for interval: Duration, clock: some Clock<Duration>) async {
        // Fast path: already stopped.
        if lock.withLock({ _isStopped }) { return }

        await withTaskGroup(of: Void.self) { group in
            // Clock task: sleeps for the interval.
            group.addTask {
                try? await clock.sleep(for: interval, tolerance: nil)
            }
            // Stop-signal task: suspends until signalStop() resumes it or
            // the task is cancelled.
            group.addTask { [self] in
                await withTaskCancellationHandler {
                    await withCheckedContinuation { cont in
                        let alreadyStopped: Bool = lock.withLock {
                            if _isStopped {
                                return true
                            }
                            sleepWaiter = cont
                            return false
                        }
                        if alreadyStopped {
                            cont.resume()
                        }
                    }
                } onCancel: { [self] in
                    let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
                        let w = sleepWaiter
                        sleepWaiter = nil
                        return w
                    }
                    waiter?.resume()
                }
            }
            // Whichever finishes first wins; cancel the other.
            await group.next()
            group.cancelAll()
        }
    }
}
