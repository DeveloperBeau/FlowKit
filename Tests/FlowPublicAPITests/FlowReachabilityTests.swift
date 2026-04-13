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
        await state.send(42)
        #expect(await state.value == 42)

        let asProtocol: any StateFlow<Int> = state
        #expect(await asProtocol.value == 42)
    }

    @Test("MutableSharedFlow and SharedFlow protocol are reachable")
    func sharedFlowReachable() async {
        let shared = MutableSharedFlow<String>(replay: 1)
        await shared.emit("event")
        let asProtocol: any SharedFlow<String> = shared
        #expect(await asProtocol.subscriptionCount == 0)
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
        let _ = await flow.reduce(0, +)
        _ = try? await flow.exactlyOne()
    }
}
