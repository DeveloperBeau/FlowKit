import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowOperators

@Suite("AsyncSequence interop")
struct AsyncSequenceInteropTests {
    // MARK: AsyncSequence → Flow

    @Test("asThrowingFlow emits every element of the sequence in order")
    func sequenceToFlow() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        for value in 1...3 { continuation.yield(value) }
        continuation.finish()

        let received = Mutex<[Int]>([])
        try await stream.asThrowingFlow().collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [1, 2, 3])
    }

    @Test("asThrowingFlow rethrows a mid-stream error after the prior values")
    func sequenceErrorPropagates() async throws {
        struct Broken: Error, Equatable {}
        let (stream, continuation) = AsyncThrowingStream<Int, any Error>.makeStream()
        continuation.yield(1)
        continuation.yield(2)
        continuation.finish(throwing: Broken())

        try await TestScope.run { scope in
            let tester = try await scope.test(stream.asThrowingFlow())
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectError(Broken())
        }
    }

    @Test("asThrowingFlow cancellation tears down the bridged sequence")
    func sequenceCancellation() async throws {
        let terminated = Mutex(false)
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        continuation.onTermination = { _ in terminated.withLock { $0 = true } }
        continuation.yield(1)
        // Never finished: only cancellation can end the iteration.

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(stream.asThrowingFlow())
            try await tester.expectValue(1)
        }
        // TestScope cancelled the collection; the stream must see termination.
        await waitUntil { terminated.withLock { $0 } }
        #expect(terminated.withLock { $0 })
    }

    @Test("asFlow bridges a non-failing sequence")
    func nonFailingSequenceToFlow() async throws {
        guard #available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) else { return }
        let (stream, continuation) = AsyncStream<String>.makeStream()
        continuation.yield("a")
        continuation.yield("b")
        continuation.finish()

        let received = Mutex<[String]>([])
        await stream.asFlow().collect { value in
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == ["a", "b"])
    }

    @Test("bridged flow composes with operators")
    func bridgedFlowThroughOperators() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        for value in 0..<10 { continuation.yield(value) }
        continuation.finish()

        let received = Mutex<[Int]>([])
        try await stream.asThrowingFlow()
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 10 }
            .collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == [0, 20, 40, 60, 80])
    }

    // MARK: Flow → AsyncSequence

    @Test("asAsyncStream yields all values and finishes")
    func flowToStream() async {
        var received: [Int] = []
        for await value in Flow(of: 1, 2, 3).asAsyncStream() {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test("asAsyncThrowingStream propagates the flow's error")
    func throwingFlowToStream() async {
        struct Broken: Error, Equatable {}
        let flow = ThrowingFlow<Int> { collector in
            try await collector.emit(1)
            throw Broken()
        }

        var received: [Int] = []
        do {
            for try await value in flow.asAsyncThrowingStream() {
                received.append(value)
            }
            Issue.record("expected the stream to throw")
        } catch let error as Broken {
            #expect(error == Broken())
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(received == [1])
    }

    @Test("abandoning the stream cancels the flow's collection")
    func streamConsumerCancellationStopsFlow() async {
        let emitting = MutableSharedFlow<Int>(replay: 0)

        // The consumer owns the stream: when its task ends, the stream is
        // released, which terminates it and cancels the bridge's collection.
        // (Merely breaking out of `for await` does not terminate an
        // AsyncStream that something else still references.)
        let consumer = Task {
            var first: Int?
            for await value in emitting.asFlow().asAsyncStream() {
                first = value
                break // abandon after one element
            }
            return first
        }

        await waitUntil { await emitting.subscriptionCount >= 1 }
        await emitting.emit(7)
        let first = await consumer.value
        #expect(first == 7)
        await waitUntil { await emitting.subscriptionCount == 0 }
        #expect(await emitting.subscriptionCount == 0)
    }

    // MARK: Round trip at volume

    @Test("10,000 elements survive a Flow → AsyncStream → ThrowingFlow round trip in order")
    func roundTripFuzz() async throws {
        let received = Mutex<[Int]>([])
        try await Flow(0..<10_000)
            .asAsyncStream()
            .asThrowingFlow()
            .collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == Array(0..<10_000))
    }
}
