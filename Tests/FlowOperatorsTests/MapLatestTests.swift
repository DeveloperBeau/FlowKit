import Testing
import FlowCore
import FlowSharedModels
import FlowHotStreams
import FlowTesting
import FlowOperators

@Suite("mapLatest / transformLatest")
struct MapLatestTests {
    @Test("mapLatest cancels the in-flight transform when a newer value arrives")
    func cancelsStaleTransform() async throws {
        let upstream = MutableSharedFlow<Int>(replay: 0)
        let firstStarted = Mutex(false)
        let firstCancelled = Mutex(false)

        let results = upstream.asFlow().mapLatest { value -> String in
            if value == 1 {
                firstStarted.withLock { $0 = true }
                // Park until cancelled; only cancellation can end this work.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                firstCancelled.withLock { $0 = true }
            }
            return "done-\(value)"
        }

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(results)
            await waitUntil { await upstream.subscriptionCount >= 1 }

            await upstream.emit(1)
            await waitUntil { firstStarted.withLock { $0 } }
            await upstream.emit(2)

            try await tester.expectValue("done-2")
            await waitUntil { firstCancelled.withLock { $0 } }
            #expect(firstCancelled.withLock { $0 })
        }
    }

    @Test("mapLatest maps every value when the upstream is paced by delivery")
    func sequentialUpstreamMapsAll() async {
        // The upstream emits the next value only after the previous result
        // was observed, so no transform is ever superseded. A free-running
        // upstream may legitimately skip intermediate results (Kotlin
        // mapLatest semantics), which under load made a plain
        // Flow(of: 1, 2, 3) version of this test flaky.
        let observed = Mutex<[Int]>([])
        let upstream = Flow<Int> { collector in
            for value in 1...3 {
                await collector.emit(value)
                await waitUntil { observed.withLock { $0 }.count >= value }
            }
        }
        await upstream.mapLatest { $0 * 10 }.collect { value in
            observed.withLock { $0.append(value) }
        }
        #expect(observed.withLock { $0 } == [10, 20, 30])
    }

    @Test("transformLatest can emit multiple values per upstream value")
    func transformEmitsMultiple() async {
        let result = await Flow(of: 1).transformLatest { value, collector in
            await collector.emit("\(value)-a")
            await collector.emit("\(value)-b")
        }.toArray()
        #expect(result == ["1-a", "1-b"])
    }

    @Test("ThrowingFlow.mapLatest propagates a transform error")
    func throwingTransformPropagates() async throws {
        struct Bad: Error, Equatable {}
        let flow = ThrowingFlow(of: 1).mapLatest { _ -> Int in throw Bad() }
        try await TestScope.run { scope in
            let tester = try await scope.test(flow)
            try await tester.expectError(Bad())
        }
    }
}
