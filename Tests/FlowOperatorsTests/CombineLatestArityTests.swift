import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowOperators

@Suite("combineLatest higher arity")
struct CombineLatestArityTests {
    @Test("three-way combineLatest emits the latest triple on every update")
    func threeWayLatest() async throws {
        let a = MutableSharedFlow<Int>(replay: 0)
        let b = MutableSharedFlow<String>(replay: 0)
        let c = MutableSharedFlow<Bool>(replay: 0)

        let combined = a.asFlow().combineLatest(b.asFlow(), c.asFlow()) { x, y, z in
            "\(x)-\(y)-\(z)"
        }

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(combined)
            await waitUntil { await a.subscriptionCount >= 1 }
            await waitUntil { await b.subscriptionCount >= 1 }
            await waitUntil { await c.subscriptionCount >= 1 }

            await a.emit(1)
            await b.emit("x")
            await c.emit(true)
            try await tester.expectValue("1-x-true")

            await b.emit("y")
            try await tester.expectValue("1-y-true")

            await a.emit(2)
            try await tester.expectValue("2-y-true")
        }
    }

    @Test("three-way tuple variant carries all components")
    func threeWayTuple() async throws {
        let combined = Flow(of: 1).combineLatest(Flow(of: "a"), Flow(of: true))
        let first = await combined.first()
        #expect(first?.0 == 1)
        #expect(first?.1 == "a")
        #expect(first?.2 == true)
    }

    @Test("four-way combineLatest waits for all four sources then combines")
    func fourWayLatest() async throws {
        let a = MutableSharedFlow<Int>(replay: 0)
        let b = MutableSharedFlow<Int>(replay: 0)
        let c = MutableSharedFlow<Int>(replay: 0)
        let d = MutableSharedFlow<Int>(replay: 0)

        let combined = a.asFlow().combineLatest(b.asFlow(), c.asFlow(), d.asFlow()) { w, x, y, z in
            w + x + y + z
        }

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(combined)
            for source in [a, b, c, d] {
                await waitUntil { await source.subscriptionCount >= 1 }
            }

            await a.emit(1)
            await b.emit(2)
            await c.emit(4)
            await tester.expectNoValue(within: .milliseconds(50)) // still missing d
            await d.emit(8)
            try await tester.expectValue(15)

            await c.emit(100)
            try await tester.expectValue(111)
        }
    }

    @Test("five-way combineLatest combines the latest of all five sources")
    func fiveWayLatest() async throws {
        let sources = (0..<5).map { _ in MutableSharedFlow<Int>(replay: 0) }
        let combined = sources[0].asFlow().combineLatest(
            sources[1].asFlow(),
            sources[2].asFlow(),
            sources[3].asFlow(),
            sources[4].asFlow()
        ) { a, b, c, d, e in a + b + c + d + e }

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(combined)
            for source in sources {
                await waitUntil { await source.subscriptionCount >= 1 }
            }
            for (index, source) in sources.enumerated() {
                await source.emit(1 << index)
            }
            try await tester.expectValue(31)

            await sources[4].emit(0)
            try await tester.expectValue(15)
        }
    }

    @Test("ThrowingFlow three-way combineLatest propagates an error from any source")
    func throwingThreeWayError() async throws {
        struct Bad: Error, Equatable {}
        let healthy = ThrowingFlow(of: 1)
        let failing = ThrowingFlow<Int> { _ in throw Bad() }

        let combined = healthy.combineLatest(ThrowingFlow(of: 2), failing) { a, b, c in a + b + c }
        try await TestScope.run { scope in
            let tester = try await scope.test(combined)
            try await tester.expectError(Bad())
        }
    }
}
