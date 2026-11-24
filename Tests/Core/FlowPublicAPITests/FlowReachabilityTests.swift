import Testing
import Flow

@Suite("Flow public API reachability")
struct FlowReachabilityTests {
    @Test("Flow type is reachable")
    func flowReachable() async {
        let flow = Flow(of: 1, 2, 3)
        let storage = Mutex<[Int]>([])
        await flow.collect { value in storage.withLock { $0.append(value) } }
        #expect(storage.withLock { $0 } == [1, 2, 3])
    }

    @Test("ThrowingFlow type is reachable")
    func throwingFlowReachable() async throws {
        let flow = ThrowingFlow(of: "a", "b")
        let storage = Mutex<[String]>([])
        try await flow.collect { value in storage.withLock { $0.append(value) } }
        #expect(storage.withLock { $0 } == ["a", "b"])
    }

    @Test("FlowScope is reachable")
    func flowScopeReachable() {
        let scope = FlowScope()
        #expect(scope.activeTaskCount == 0)
    }

    @Test("AsyncSequence bridges are reachable")
    func asyncSequenceBridgesReachable() async throws {
        var streamed: [Int] = []
        for await value in Flow(of: 1, 2).asAsyncStream() {
            streamed.append(value)
        }
        #expect(streamed == [1, 2])

        let (stream, continuation) = AsyncStream<Int>.makeStream()
        continuation.yield(3)
        continuation.finish()
        let collected = Mutex<[Int]>([])
        try await stream.asThrowingFlow().collect { value in
            collected.withLock { $0.append(value) }
        }
        #expect(collected.withLock { $0 } == [3])
    }

    @Test("Kotlin-parity additions are reachable")
    func parityAdditionsReachable() async throws {
        let chunked = await Flow(0..<5).chunks(ofCount: 2).toArray()
        #expect(chunked == [[0, 1], [2, 3], [4]])
        #expect(await Flow(of: 1, 2, 3).drop(while: { $0 < 3 }).last() == 3)
        #expect(await Flow(of: 2, 4).allSatisfy { $0.isMultiple(of: 2) })

        let combined = await Flow(of: 1).combineLatest(Flow(of: 2), Flow(of: 3)) { $0 + $1 + $2 }.first()
        #expect(combined == 6)

        let timed = Flow(of: "ok").timeout(for: .seconds(5))
        let received = Mutex<[String]>([])
        try await timed.collect { value in received.withLock { $0.append(value) } }
        #expect(received.withLock { $0 } == ["ok"])
    }

    @Test("Throwing channelFlow and callbackFlow are reachable")
    func throwingChannelBuildersReachable() async {
        struct Failed: Error {}
        let channel = ThrowingFlow<Int>.channelFlow { scope in
            scope.trySend(1)
            scope.close()
        }
        let callback = ThrowingFlow<Int>.callbackFlow { (scope: ThrowingProducerScope<Int>) in
            await scope.send(2)
            scope.close(throwing: Failed())
            await scope.awaitClose()
        }
        let received = Mutex<[Int]>([])
        await #expect(throws: Failed.self) {
            try await channel.collect { value in received.withLock { $0.append(value) } }
            try await callback.collect { value in received.withLock { $0.append(value) } }
        }
        #expect(received.withLock { $0 } == [1, 2])
    }

    @Test("Transform operators are reachable")
    func operatorsReachable() async {
        let flow = Flow(of: 1, 2, 3, 4, 5)
            .filter { $0 > 2 }
            .map { $0 * 10 }
            .prefix(2)

        let storage = Mutex<[Int]>([])
        await flow.collect { value in storage.withLock { $0.append(value) } }
        #expect(storage.withLock { $0 } == [30, 40])
    }

    @Test("MutableStateFlow and StateFlow protocol are reachable")
    func stateFlowReachable() async {
        let state = MutableStateFlow(0)
        state.send(42)
        #expect(state.value == 42)

        let asProtocol: any StateFlow<Int> = state
        #expect(asProtocol.value == 42)
    }

    @Test("MutableSharedFlow and SharedFlow protocol are reachable")
    func sharedFlowReachable() async {
        let shared = MutableSharedFlow<String>(replay: 1)
        await shared.emit("event")
        let asProtocol: any SharedFlow<String> = shared
        #expect(await asProtocol.subscriptionCount == 0)
    }

    @Test("subscribed() is reachable on both mutable hot flows")
    func subscribedReachable() async {
        let shared = MutableSharedFlow<String>()
        let events = shared.subscribed()
        await shared.emit("event")
        #expect(await events.first() == "event")

        let state = MutableStateFlow(0)
        let changes = state.subscribed()
        state.send(42)
        #expect(await changes.prefix(2).toArray() == [0, 42])
    }

    @Test("close is reachable on both mutable hot flows and ends a collection")
    func closeReachable() async {
        let state = MutableStateFlow(1)
        state.close()
        let stateValues = Mutex<[Int]>([])
        await state.asFlow().collect { value in stateValues.withLock { $0.append(value) } }
        #expect(stateValues.withLock { $0 } == [1])

        let shared = MutableSharedFlow<Int>(replay: 1)
        await shared.emit(1)
        await shared.close()
        let sharedValues = Mutex<[Int]>([])
        await shared.asFlow().collect { value in sharedValues.withLock { $0.append(value) } }
        #expect(sharedValues.withLock { $0 } == [])
    }

    @Test("MutableSharedFlow.tryEmit is callable from a function that is not async")
    func tryEmitReachableFromSynchronousCode() async {
        // A plain closure type has no `async`, so this compiles only while
        // `tryEmit` needs no `await`.
        let shared = MutableSharedFlow<String>(replay: 1)
        let publish: @Sendable (String) -> Bool = { shared.tryEmit($0) }
        #expect(publish("event"))
        #expect(await shared.replayCache == ["event"])
    }

    @Test("SharingStrategy and BufferOverflow are reachable")
    func sharedModelsReachable() {
        let strategy: SharingStrategy = .whileSubscribed(stopTimeout: .seconds(5))
        let overflow: BufferOverflow = .dropOldest
        #expect(strategy != .eager)
        #expect(overflow == .dropOldest)
    }

    @Test("asStateFlow and asSharedFlow conversions are reachable")
    func conversionsReachable() async {
        let coldFlow = Flow(of: 1, 2, 3)
        let _: any StateFlow<Int> = coldFlow.asStateFlow(initialValue: 0, strategy: .lazy)
        let _: any SharedFlow<Int> = coldFlow.asSharedFlow(replay: 0, strategy: .lazy)
    }

    @Test("flatMap and flatMapLatest are reachable")
    func flatteningReachable() async {
        let flow = Flow(of: 1, 2)
        let _ = flow.flatMap { Flow(of: $0) }
        let _ = flow.flatMapLatest { Flow(of: $0) }
    }

    @Test("zip, combineLatest, and merge are reachable")
    func combiningReachable() async {
        let flow1 = Flow(of: 1)
        let flow2 = Flow(of: "a")
        let _ = flow1.zip(flow2)
        let _ = flow1.combineLatest(Flow(of: 2))
        let _ = Flow.merge(Flow(of: 1), Flow(of: 2))
    }

    @Test("catch, retry, retryWhen are reachable")
    func errorHandlingReachable() async {
        let flow = ThrowingFlow(of: 1)
        let _ = flow.catch { _, _ in }
        let _ = flow.retry(3)
        let _ = flow.retryWhen { _, _ in false }
    }

    @Test("debounce, throttle, removeDuplicates, sample are reachable")
    func rateLimitingReachable() async {
        let flow = Flow(of: 1, 2, 2, 3)
        let _ = flow.debounce(for: .seconds(1))
        let _ = flow.throttle(for: .seconds(1))
        let _ = flow.removeDuplicates()
        let _ = flow.sample(every: .seconds(1))
    }

    @Test("buffer and keepingLatest are reachable")
    func bufferingReachable() async {
        let flow = Flow(of: 1, 2, 3)
        let _ = flow.buffer(size: 10, policy: .dropOldest)
        let _ = flow.keepingLatest()
    }

    @Test("terminal operators are reachable")
    func terminalReachable() async throws {
        let flow = Flow(of: 1, 2, 3)
        let _ = await flow.first()
        let _ = await flow.toArray()
        let _ = await flow.reduce(0) { $0 + $1 }
        _ = try? await flow.exactlyOne()
    }
}
