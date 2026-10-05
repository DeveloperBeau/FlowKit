import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
@testable import FlowHotStreams

/// A concrete hot stream under test, so one scenario runs against both.
enum HotStream: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case shared = "MutableSharedFlow"
    case state = "MutableStateFlow"

    var testDescription: String { rawValue }

    /// Runs `body` against a fresh stream, then detaches every collector it attached.
    func withSubject(_ body: (Subject) async throws -> Void) async throws {
        let subject = await makeSubject()
        defer { subject.detachAll() }
        try await body(subject)
    }

    private func makeSubject() async -> Subject {
        switch self {
        case .shared:
            // Replay of one: the cached value is delivered after the
            // subscription registers, so a collector's first value proves it.
            let flow = MutableSharedFlow<Int>(replay: 1)
            await flow.emit(0)
            return Subject(
                waitAtLeast: { try await flow.waitForSubscribers($0) },
                waitAtMost: { try await flow.waitForSubscribers(atMost: $0) },
                collect: { await flow.asFlow().collect($0) }
            )
        case .state:
            // The snapshot is emitted after the subscription registers.
            let flow = MutableStateFlow(0)
            return Subject(
                waitAtLeast: { try await flow.waitForSubscribers($0) },
                waitAtMost: { try await flow.waitForSubscribers(atMost: $0) },
                collect: { await flow.asFlow().collect($0) }
            )
        }
    }

    final class Subject: Sendable {
        let waitAtLeast: @Sendable (Int) async throws -> Void
        let waitAtMost: @Sendable (Int) async throws -> Void
        private let collect: @Sendable (@escaping @Sendable (Int) async -> Void) async -> Void
        private let collectors = Mutex<[Task<Void, Never>]>([])

        init(
            waitAtLeast: @escaping @Sendable (Int) async throws -> Void,
            waitAtMost: @escaping @Sendable (Int) async throws -> Void,
            collect: @escaping @Sendable (@escaping @Sendable (Int) async -> Void) async -> Void
        ) {
            self.waitAtLeast = waitAtLeast
            self.waitAtMost = waitAtMost
            self.collect = collect
        }

        /// Attaches a collector and returns it once registered, so the count
        /// is known to include it. Cancel the task to detach it.
        func attach() async -> Task<Void, Never> {
            let registered = Signal()
            let collect = collect
            let task = Task { await collect { _ in registered.fire() } }
            collectors.withLock { $0.append(task) }
            await registered.wait()
            return task
        }

        func detachAll() {
            for task in collectors.withLock({ $0 }) { task.cancel() }
        }
    }
}

/// Runs `wait` in its own task and reports when it returns.
private func startWaiter(
    _ wait: @escaping @Sendable () async throws -> Void
) -> (task: Task<Void, any Error>, returned: Signal) {
    let returned = Signal()
    let task = Task {
        try await wait()
        returned.fire()
    }
    return (task, returned)
}

@Suite("Hot stream subscriber waiters")
struct SubscriberWaiterTests {
    @Test("waitForSubscribers returns at once when the count is already met", arguments: HotStream.allCases)
    func atLeastAlreadyMet(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            // Zero is met by an empty stream.
            let none = startWaiter { try await subject.waitAtLeast(0) }
            #expect(await none.returned.firesWithinHops(), "wait for 0 did not return on an empty stream")

            _ = await subject.attach()
            let exact = startWaiter { try await subject.waitAtLeast(1) }
            #expect(await exact.returned.firesWithinHops(), "wait for 1 did not return with exactly 1 attached")
        }
    }

    @Test("waitForSubscribers suspends until enough collectors attach", arguments: HotStream.allCases)
    func atLeastSuspendsThenResumes(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            _ = await subject.attach()
            let waiter = startWaiter { try await subject.waitAtLeast(2) }
            #expect(!(await waiter.returned.firesWithinHops()), "returned with 1 of 2 collectors")

            _ = await subject.attach()
            #expect(await waiter.returned.firesWithinHops(), "did not return once the second collector attached")
        }
    }

    @Test("waitForSubscribers resumes only the waiters whose count is met", arguments: HotStream.allCases)
    func atLeastResumesEachAtItsCount(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            let one = startWaiter { try await subject.waitAtLeast(1) }
            let oneToo = startWaiter { try await subject.waitAtLeast(1) }
            let three = startWaiter { try await subject.waitAtLeast(3) }

            _ = await subject.attach()
            #expect(await one.returned.firesWithinHops(), "first waiter for 1 stayed parked")
            #expect(await oneToo.returned.firesWithinHops(), "second waiter for 1 stayed parked")
            #expect(!(await three.returned.firesWithinHops()), "waiter for 3 returned with 1 collector")
            three.task.cancel()
        }
    }

    @Test("waitForSubscribers(atMost:) returns at once when the count is already low enough", arguments: HotStream.allCases)
    func atMostAlreadyMet(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            let empty = startWaiter { try await subject.waitAtMost(0) }
            #expect(await empty.returned.firesWithinHops(), "atMost 0 did not return on an empty stream")

            _ = await subject.attach()
            let exact = startWaiter { try await subject.waitAtMost(1) }
            #expect(await exact.returned.firesWithinHops(), "atMost 1 did not return with exactly 1 attached")
        }
    }

    @Test("waitForSubscribers(atMost:) suspends until collectors detach", arguments: HotStream.allCases)
    func atMostSuspendsThenResumes(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            let first = await subject.attach()
            let second = await subject.attach()
            let toOne = startWaiter { try await subject.waitAtMost(1) }
            let toZero = startWaiter { try await subject.waitAtMost(0) }
            #expect(!(await toOne.returned.firesWithinHops()), "returned with 2 attached")

            second.cancel()
            #expect(await toOne.returned.firesWithinHops(), "did not return once the count fell to 1")
            #expect(!(await toZero.returned.firesWithinHops()), "waiter for 0 returned with 1 attached")

            first.cancel()
            #expect(await toZero.returned.firesWithinHops(), "did not return once the count fell to 0")
        }
    }

    @Test("Cancelling a waiter ends it with CancellationError", arguments: HotStream.allCases)
    func cancellationThrows(stream: HotStream) async throws {
        try await stream.withSubject { subject in
            // Neither condition can be met here (5 collectors, or fewer than
            // none), so only cancellation can end the wait.
            let waits: [@Sendable () async throws -> Void] = [
                { try await subject.waitAtLeast(5) },
                { try await subject.waitAtMost(-1) },
            ]
            for wait in waits {
                let ended = Signal()
                let thrown = Mutex<(any Error)?>(nil)
                let task = Task {
                    do { try await wait() } catch { thrown.withLock { $0 = error } }
                    ended.fire()
                }
                // Give the waiter time to park, so the cancel reaches the
                // handler rather than the cancelled-before-waiting check.
                for _ in 0..<200 { await Task.yield() }
                task.cancel()
                #expect(await ended.firesWithinHops(), "a cancelled waiter stayed parked")
                #expect(thrown.withLock { $0 } is CancellationError)
            }
        }
    }
}
