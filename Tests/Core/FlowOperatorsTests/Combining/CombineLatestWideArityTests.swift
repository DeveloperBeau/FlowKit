import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowTestSupport
import FlowOperators

@Suite("combineLatest wide arity (4/5/6)")
struct CombineLatestWideArityTests {
    // MARK: - Flow, six sources

    @Test("six-way combineLatest stays silent until every source has emitted")
    func sixWaySilentUntilAllEmit() async throws {
        let sources = (0..<6).map { _ in MutableSharedFlow<Int>(replay: 0) }
        let combined = sources[0].asFlow().combineLatest(
            sources[1].asFlow(),
            sources[2].asFlow(),
            sources[3].asFlow(),
            sources[4].asFlow(),
            sources[5].asFlow()
        ) { a, b, c, d, e, f in a + b + c + d + e + f }

        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            for source in sources {
                await pollUntil { await source.subscriptionCount >= 1 }
            }

            // Five of six emitted: still silent.
            for (index, source) in sources.dropLast().enumerated() {
                await source.emit(1 << index)
            }
            // The first read below is the sixth source's pairing, so a value
            // emitted early would fail it.

            await sources[5].emit(32)
            try await tester.expectValue(63)

            // One source updates: combined re-emits with the latest of the others.
            await sources[2].emit(0)
            try await tester.expectValue(59)
        }
    }

    @Test("six-way tuple variant carries all components")
    func sixWayTuple() async throws {
        let combined = Flow(of: 1).combineLatest(
            Flow(of: "a"),
            Flow(of: true),
            Flow(of: 2),
            Flow(of: "b"),
            Flow(of: false)
        )
        let first = await combined.first()
        #expect(first?.0 == 1)
        #expect(first?.1 == "a")
        #expect(first?.2 == true)
        #expect(first?.3 == 2)
        #expect(first?.4 == "b")
        #expect(first?.5 == false)
    }

    @Test("six-way combineLatest with a never-emitting source stays silent")
    func sixWayNeverEmittingSourceStaysSilent() async throws {
        let sources = (0..<5).map { _ in MutableSharedFlow<Int>(replay: 0) }
        let never = MutableSharedFlow<Int>(replay: 0)
        let combined = sources[0].asFlow().combineLatest(
            sources[1].asFlow(),
            sources[2].asFlow(),
            sources[3].asFlow(),
            sources[4].asFlow(),
            never.asFlow()
        ) { a, b, c, d, e, f in a + b + c + d + e + f }

        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            for source in sources {
                await pollUntil { await source.subscriptionCount >= 1 }
            }
            await pollUntil { await never.subscriptionCount >= 1 }

            for source in sources {
                await source.emit(1)
                await source.emit(2)
            }
            // Nothing yet: the first value is one the late source unlocks, so it
            // carries its 100. The five others settle on 2 each, a sum of 10,
            // and may still be mid-delivery when the first value is formed.
            await never.emit(100)
            let first = try await tester.awaitValue()
            #expect(first >= 100, "a value before the sixth source emitted would be below 100")
            if first != 110 { try await tester.awaitValue(equalTo: 110) }
        }
    }

    @Test("a source completing without emitting completes the combined flow")
    func sourceCompletingWithoutEmittingCompletes() async throws {
        // Kotlin's combine cannot produce a tuple once a source ends valueless;
        // the combined flow completes. Pin that here.
        let live = MutableSharedFlow<Int>(replay: 0)
        let empty = Flow<Int> { _ in }
        let combined = live.asFlow().combineLatest(
            live.asFlow(), live.asFlow(), live.asFlow(), live.asFlow(), empty
        ) { a, b, c, d, e, f in a + b + c + d + e + f }

        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            try await tester.expectCompletion()
        }
    }

    @Test("a source completing after emitting holds its last value")
    func sourceCompletingAfterEmittingHoldsLastValue() async throws {
        let finite = Flow(of: 100)
        let sources = (0..<5).map { _ in MutableSharedFlow<Int>(replay: 0) }
        let combined = finite.combineLatest(
            sources[0].asFlow(),
            sources[1].asFlow(),
            sources[2].asFlow(),
            sources[3].asFlow(),
            sources[4].asFlow()
        ) { a, b, c, d, e, f in a + b + c + d + e + f }

        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            for source in sources {
                await pollUntil { await source.subscriptionCount >= 1 }
            }
            for source in sources {
                await source.emit(1)
            }
            try await tester.expectValue(105)

            // The completed source's last value stays in the combination.
            await sources[0].emit(2)
            try await tester.expectValue(106)
        }
    }

    @Test("concurrent update storm converges on the final source values with no extra emissions")
    func sixWayUpdateStorm() async throws {
        let sources = (0..<6).map { _ in MutableSharedFlow<Int>(replay: 1) }
        let combined = sources[0].asFlow().combineLatest(
            sources[1].asFlow(),
            sources[2].asFlow(),
            sources[3].asFlow(),
            sources[4].asFlow(),
            sources[5].asFlow()
        ) { a, b, c, d, e, f in [a, b, c, d, e, f] }

        let emissions = Recorder<[Int]>()
        let subscriber = Task {
            await combined.collect { value in
                emissions.record(value)
            }
        }
        for source in sources {
            await pollUntil { await source.subscriptionCount >= 1 }
        }

        // Each source is hammered by its own task; the last value per source
        // is deterministic (its program order), so the converged combination is too.
        let perSourceFinal = 20
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask {
                    for value in 1...perSourceFinal {
                        await source.emit(value)
                    }
                }
            }
        }

        let expected = Array(repeating: perSourceFinal, count: 6)
        await emissions.wait { $0.last == expected }
        #expect(emissions.last == expected, "the last emission of every source must survive the storm")

        // No duplicate emissions after quiescence.
        let settled = emissions.count
        for _ in 0..<100 { await Task.yield() }
        #expect(emissions.count == settled, "a quiescent combination must not re-emit")

        subscriber.cancel()
    }

    // MARK: - ThrowingFlow, four/five/six sources

    @Test("ThrowingFlow four-way combineLatest combines the latest of all sources")
    func throwingFourWayLatest() async throws {
        let combined = ThrowingFlow(of: 1).combineLatest(
            ThrowingFlow(of: 2),
            ThrowingFlow(of: 4),
            ThrowingFlow(of: 8)
        ) { a, b, c, d in a + b + c + d }
        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            try await tester.expectValue(15)
        }
    }

    @Test("ThrowingFlow five-way tuple variant carries all components")
    func throwingFiveWayTuple() async throws {
        let combined = ThrowingFlow(of: 1).combineLatest(
            ThrowingFlow(of: 2),
            ThrowingFlow(of: 3),
            ThrowingFlow(of: 4),
            ThrowingFlow(of: 5)
        )
        try await ProbeScope.run { scope in
            let tester = scope.probe(combined.map { [$0.0, $0.1, $0.2, $0.3, $0.4] })
            try await tester.expectValue([1, 2, 3, 4, 5])
        }
    }

    @Test("ThrowingFlow six-way combineLatest propagates an error from any source")
    func throwingSixWayError() async throws {
        struct Bad: Error, Equatable {}
        let failing = ThrowingFlow<Int> { _ in throw Bad() }
        let first: ThrowingFlow<Int> = ThrowingFlow(of: 1)
        let second: ThrowingFlow<Int> = ThrowingFlow(of: 2)
        let third: ThrowingFlow<Int> = ThrowingFlow(of: 3)
        let fourth: ThrowingFlow<Int> = ThrowingFlow(of: 4)
        let fifth: ThrowingFlow<Int> = ThrowingFlow(of: 5)
        let combined: ThrowingFlow<Int> = first.combineLatest(second, third, fourth, fifth, failing) {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in a + b + c + d + e + f
        }
        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            try await tester.expectError(Bad())
        }
    }

    @Test("ThrowingFlow six-way combineLatest combines when all sources emit")
    func throwingSixWayLatest() async throws {
        let first: ThrowingFlow<Int> = ThrowingFlow(of: 1)
        let second: ThrowingFlow<Int> = ThrowingFlow(of: 2)
        let third: ThrowingFlow<Int> = ThrowingFlow(of: 4)
        let fourth: ThrowingFlow<Int> = ThrowingFlow(of: 8)
        let fifth: ThrowingFlow<Int> = ThrowingFlow(of: 16)
        let sixth: ThrowingFlow<Int> = ThrowingFlow(of: 32)
        let combined: ThrowingFlow<Int> = first.combineLatest(second, third, fourth, fifth, sixth) {
            (a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in a + b + c + d + e + f
        }
        try await ProbeScope.run { scope in
            let tester = scope.probe(combined)
            try await tester.expectValue(63)
        }
    }
}
