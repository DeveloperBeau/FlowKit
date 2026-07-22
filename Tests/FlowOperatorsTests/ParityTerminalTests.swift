import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowOperators

@Suite("last / count / contains / allSatisfy terminals")
struct ParityTerminalTests {
    @Test("last returns the final value")
    func lastValue() async {
        #expect(await Flow(of: 1, 2, 3).last() == 3)
    }

    @Test("last on an empty flow returns nil")
    func lastEmpty() async {
        #expect(await Flow<Int>.empty.last() == nil)
    }

    @Test("count returns the number of emissions")
    func countValues() async {
        #expect(await Flow(0..<500).count() == 500)
        #expect(await Flow<Int>.empty.count() == 0)
    }

    @Test("contains(where:) finds a match and reports absence")
    func containsWhere() async {
        #expect(await Flow(of: 1, 2, 3).contains(where: { $0 == 2 }))
        #expect(await !Flow(of: 1, 2, 3).contains(where: { $0 == 9 }))
    }

    @Test("allSatisfy holds for all-matching, fails on one miss, and is true for empty")
    func allSatisfyCases() async {
        #expect(await Flow(of: 2, 4, 6).allSatisfy { $0.isMultiple(of: 2) })
        #expect(await !Flow(of: 2, 3, 6).allSatisfy { $0.isMultiple(of: 2) })
        #expect(await Flow<Int>.empty.allSatisfy { _ in false })
    }
}

@Suite("onEmpty operator")
struct OnEmptyTests {
    @Test("onEmpty emits the fallback when the flow completes without values")
    func fallbackOnEmpty() async {
        let result = await Flow<Int>.empty
            .onEmpty { collector in await collector.emit(42) }
            .toArray()
        #expect(result == [42])
    }

    @Test("onEmpty stays silent when the flow emits")
    func silentWhenNonEmpty() async {
        let invoked = Mutex(false)
        let result = await Flow(of: 1)
            .onEmpty { _ in invoked.withLock { $0 = true } }
            .toArray()
        #expect(result == [1])
        #expect(!invoked.withLock { $0 })
    }

    @Test("a failing upstream rethrows without invoking onEmpty")
    func errorSkipsOnEmpty() async throws {
        struct Bad: Error, Equatable {}
        let invoked = Mutex(false)
        let flow = ThrowingFlow<Int> { _ in throw Bad() }
            .onEmpty { _ in invoked.withLock { $0 = true } }
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectError(Bad())
        }
        #expect(!invoked.withLock { $0 })
    }
}

@Suite("Collector.emitAll")
struct EmitAllTests {
    @Test("emitAll splices another flow's values into a flow body")
    func splicesValues() async {
        let combined = Flow<Int> { collector in
            await collector.emit(0)
            await collector.emitAll(Flow(of: 1, 2))
            await collector.emit(3)
        }
        #expect(await combined.toArray() == [0, 1, 2, 3])
    }

    @Test("ThrowingCollector.emitAll rethrows the spliced flow's error")
    func splicedErrorPropagates() async throws {
        struct Bad: Error, Equatable {}
        let combined = ThrowingFlow<Int> { collector in
            try await collector.emit(0)
            try await collector.emitAll(ThrowingFlow { inner in
                try await inner.emit(1)
                throw Bad()
            })
        }
        try await TestScope.run { scope in
            let tester = try await scope.test(combined)
            try await tester.expectValue(0)
            try await tester.expectValue(1)
            try await tester.expectError(Bad())
        }
    }

    @Test("emitAll of an empty flow returns immediately and the body continues")
    func emptyFlowReturnsImmediately() async {
        let combined = Flow<Int> { collector in
            await collector.emit(0)
            await collector.emitAll(Flow<Int>.empty)
            await collector.emit(1)
        }
        #expect(await combined.toArray() == [0, 1])
    }

    @Test("ThrowingCollector.emitAll of an empty flow returns immediately")
    func throwingEmptyFlowReturnsImmediately() async throws {
        let combined = ThrowingFlow<Int> { collector in
            try await collector.emit(0)
            try await collector.emitAll(ThrowingFlow<Int> { _ in })
            try await collector.emit(1)
        }
        try await TestScope.run { scope in
            let tester = try await scope.test(combined)
            try await tester.expectValue(0)
            try await tester.expectValue(1)
            try await tester.expectCompletion()
        }
    }

    @Test("cancellation mid-emitAll stops the inner collection promptly")
    func cancellationStopsInnerCollection() async {
        let inner = MutableSharedFlow<Int>(replay: 0)
        let received = Mutex<[Int]>([])

        let outer = Flow<Int> { collector in
            await collector.emitAll(inner.asFlow())
        }
        let subscriber = Task {
            await outer.collect { value in
                received.withLock { $0.append(value) }
            }
        }
        await waitUntil { await inner.subscriptionCount >= 1 }

        await inner.emit(1)
        await inner.emit(2)
        await waitUntil { received.withLock { $0.count } >= 2 }

        subscriber.cancel()
        // The cancelled subscriber must detach from the inner flow; emissions
        // after that must not be delivered.
        await waitUntil { await inner.subscriptionCount == 0 }
        #expect(await inner.subscriptionCount == 0, "cancellation must tear down the inner subscription")

        await inner.emit(3)
        for _ in 0..<100 { await Task.yield() }
        #expect(received.withLock { $0 } == [1, 2], "no delivery after cancellation")
    }
}
