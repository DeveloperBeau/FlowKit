import CryptoKit
import Flow
import FlowTesting
import Foundation
import Testing

// MARK: - Simulated world

/// A GPS fix as produced by a simulated location service.
private struct LocationFix: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var tick: Int
}

private struct SensorReading: Codable, Equatable, Sendable {
    var id: Int
    var celsius: Double
}

private struct DashboardSnapshot: Equatable, Sendable {
    var latitude: Double
    var uploadCount: Int
}

/// AES-GCM over JSON, the way a real telemetry pipeline wraps payloads.
private enum Sealed {
    static func randomKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    static func encrypt(_ value: some Encodable, keyData: Data) throws -> Data {
        let json = try JSONEncoder().encode(value)
        // combined is always non-nil with the default 12-byte nonce
        return try AES.GCM.seal(json, using: SymmetricKey(data: keyData)).combined!
    }

    static func decrypt<T: Decodable>(_ type: T.Type, from blob: Data, keyData: Data) throws -> T {
        let box = try AES.GCM.SealedBox(combined: blob)
        let json = try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        return try JSONDecoder().decode(type, from: json)
    }
}

/// Imaginary backend. Records uploads and can fail a set number of times.
private actor MockBackend {
    struct Unavailable: Error {}

    private(set) var uploads: [Data] = []
    private(set) var attempts = 0
    private var failuresRemaining: Int

    init(failing failures: Int = 0) {
        self.failuresRemaining = failures
    }

    func upload(_ blob: Data) throws {
        attempts += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Unavailable()
        }
        uploads.append(blob)
    }
}

/// Imaginary search service. Records every query that actually reaches it.
private actor SearchService {
    private(set) var queries: [String] = []

    func search(_ query: String) -> [String] {
        queries.append(query)
        return ["\(query)-result-1", "\(query)-result-2"]
    }
}

private actor StartCounter {
    private(set) var starts = 0
    func increment() { starts += 1 }
}

// MARK: - Scenarios

@Suite("Simulation: FlowKit in the wild")
struct SimulationTests {
    // MARK: 1. Location telemetry (high-frequency source, interval upload)

    @Test("GPS firehose is sampled on an interval, encrypted, JSON-encoded, and uploaded")
    func locationTelemetryPipeline() async throws {
        let clock = TestClock()
        let keyData = Sealed.randomKey()
        let gps = MutableSharedFlow<LocationFix>(replay: 0)
        let backend = MockBackend()
        let delivered = FlowProbe<LocationFix>()

        // High-frequency fixes → keep only the latest per 30s window →
        // encrypt + encode → upload. The shape of a real telemetry agent.
        let pipeline = gps.asFlow()
            .tap(after: delivered)
            .sample(every: .seconds(30), clock: clock)
            .mapThrowing { fix in try Sealed.encrypt(fix, keyData: keyData) }
            .map { blob in
                try await backend.upload(blob)
                return blob
            }

        try await TestScope.run(timeout: .seconds(30)) { scope in
            let tester = try await scope.test(pipeline)
            await waitUntil { await gps.subscriptionCount >= 1 }
            await waitUntil { clock.sleeperCount >= 1 }

            // Burst 1: 200 fixes inside the first window.
            for tick in 0..<200 {
                await gps.emit(
                    LocationFix(latitude: 51.5 + Double(tick) / 10_000, longitude: -0.12, tick: tick)
                )
            }
            await waitUntil { await delivered.last?.tick == 199 }
            await clock.advance(by: .seconds(30))

            let firstUpload = try await tester.awaitValue()
            let firstFix = try Sealed.decrypt(LocationFix.self, from: firstUpload, keyData: keyData)
            #expect(firstFix.tick == 199) // only the latest fix survives sampling

            // Burst 2: a quieter window.
            await waitUntil { clock.sleeperCount >= 1 }
            for tick in 200..<220 {
                await gps.emit(LocationFix(latitude: 51.6, longitude: -0.12, tick: tick))
            }
            await waitUntil { await delivered.last?.tick == 219 }
            await clock.advance(by: .seconds(30))

            let secondUpload = try await tester.awaitValue()
            let secondFix = try Sealed.decrypt(LocationFix.self, from: secondUpload, keyData: keyData)
            #expect(secondFix.tick == 219)

            #expect(await backend.uploads.count == 2)
            await tester.cancelAndIgnoreRemaining()
        }
    }

    // MARK: 2. Encrypted container sync (failure injection, retry)

    @Test("encrypted container sync retries through transient backend outages")
    func containerSyncSurvivesFlakyBackend() async throws {
        let keyData = Sealed.randomKey()
        let backend = MockBackend(failing: 2)
        let stored = (1...3).map { SensorReading(id: $0, celsius: 18.5 + Double($0)) }
        // "Some container" of encrypted blobs, e.g. an app-group file store.
        let container: [Data] = try stored.map { try Sealed.encrypt($0, keyData: keyData) }

        let sync = ThrowingFlow<SensorReading> { collector in
            for blob in container {
                try await backend.upload(blob)
                let reading = try Sealed.decrypt(SensorReading.self, from: blob, keyData: keyData)
                try await collector.emit(reading)
            }
        }
        .retry(3, shouldRetry: { $0 is MockBackend.Unavailable })

        try await TestScope.run { scope in
            let tester = try await scope.test(sync)
            for reading in stored {
                try await tester.expectValue(reading)
            }
            try await tester.expectCompletion()
        }

        // Two failed attempts died on the first blob; the third pushed all three.
        #expect(await backend.attempts == 5)
        #expect(await backend.uploads == container)
    }

    // MARK: 3. Sensor firehose (volume, backpressure)

    @Test("a 10,000-event firehose through a suspending buffer arrives lossless and ordered")
    func sensorFirehoseBackpressure() async throws {
        let received = await Flow(0..<10_000)
            .buffer(size: 64, policy: .suspend)
            .map { value in
                // A consumer that periodically stalls, forcing the producer to
                // suspend on the full buffer instead of dropping.
                if value % 512 == 0 { await Task.yield() }
                return value
            }
            .toArray()

        #expect(received == Array(0..<10_000))
    }

    // MARK: 4. Search-as-you-type (bursty human input, cancellation)

    @Test("bursty typing debounces so only the settled query hits the backend")
    func debouncedSearchOnlyQueriesOnce() async throws {
        let clock = TestClock()
        let keystrokes = MutableSharedFlow<String>(replay: 0)
        let service = SearchService()
        let typed = FlowProbe<String>()

        let results = keystrokes.asFlow()
            .tap(after: typed)
            .debounce(for: .milliseconds(300), clock: clock)
            .removeDuplicates()
            .flatMapLatest { query in
                Flow { collector in
                    await collector.emit(await service.search(query))
                }
            }

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let tester = try await scope.test(results)
            await waitUntil { await keystrokes.subscriptionCount >= 1 }

            await keystrokes.emit("f")
            await waitUntil { await typed.last == "f" }
            await clock.advance(by: .milliseconds(100))
            await keystrokes.emit("fl")
            await waitUntil { await typed.last == "fl" }
            await clock.advance(by: .milliseconds(100))
            await keystrokes.emit("flow")
            await waitUntil { await typed.last == "flow" }

            // Still typing: nothing has reached the backend.
            await tester.expectNoValue(within: .milliseconds(50))

            await clock.advance(by: .milliseconds(300))
            try await tester.expectValue(["flow-result-1", "flow-result-2"])
        }

        #expect(await service.queries == ["flow"])
    }

    // MARK: 5. Shared dashboard (multi-subscriber fan-out, share-once)

    @Test("combined app state fans out to multiple subscribers from one shared upstream")
    func sharedDashboardFanOut() async throws {
        let location = MutableStateFlow(LocationFix(latitude: 51.5, longitude: -0.12, tick: 0))
        let uploadCount = MutableStateFlow(0)
        let starts = StartCounter()

        let dashboard = location.asFlow()
            .onStart { await starts.increment() }
            .combineLatest(uploadCount.asFlow()) { fix, uploads in
                DashboardSnapshot(latitude: fix.latitude, uploadCount: uploads)
            }
            .asSharedFlow(replay: 1)

        try await TestScope.run(timeout: .seconds(15)) { scope in
            let screenA = try await scope.test(dashboard.asFlow())
            let screenB = try await scope.test(dashboard.asFlow())

            let initial = DashboardSnapshot(latitude: 51.5, uploadCount: 0)
            await waitUntil { await screenA.receivedValues().contains(initial) }
            await waitUntil { await screenB.receivedValues().contains(initial) }

            await location.update { fix in
                var fix = fix
                fix.latitude = 52.0
                fix.tick += 1
                return fix
            }
            await uploadCount.send(1)

            let final = DashboardSnapshot(latitude: 52.0, uploadCount: 1)
            await waitUntil { await screenA.receivedValues().contains(final) }
            await waitUntil { await screenB.receivedValues().contains(final) }
        }

        // Both screens observed the same pipeline; the upstream ran once.
        #expect(await starts.starts == 1)
    }
}
