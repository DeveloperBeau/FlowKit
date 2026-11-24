import Testing
import Flow
import FlowRecording

@Suite("FlowRecorder fuzz")
struct FlowRecorderFuzzTests {
    @Test("Seeded fuzz: every waiter gets an ordered prefix that reaches its count or the whole flow")
    func seededFuzzOfWaiters() async throws {
        let seed: UInt64 = 0x5EED_F10E_2EC0_4D01
        print("FlowRecorder fuzz seed: \(seed)")
        var generator = SplitMix64(state: seed)
        for round in 0..<200 {
            let length = Int.random(in: 0...64, using: &generator)
            let expected = (0..<length).map { _ in Int.random(in: -1000...1000, using: &generator) }
            let counts = (0..<4).map { _ in Int.random(in: -2...80, using: &generator) }
            let fails = Bool.random(using: &generator)

            let recorder: FlowRecorder<Int>
            if fails {
                recorder = FlowRecorder(ThrowingFlow<Int> { collector in
                    for value in expected { try await collector.emit(value) }
                    throw FuzzError()
                })
            } else {
                recorder = FlowRecorder(Flow(expected))
            }
            let waiters = counts.map { count in
                Task { await recorder.values(atLeast: count) }
            }
            for (waiter, count) in zip(waiters, counts) {
                let values = try await bounded("round \(round): wait for \(count) of \(length)") {
                    await waiter.value
                }
                #expect(values.count >= min(max(count, 0), length), "round \(round), seed \(seed)")
                #expect(values == Array(expected.prefix(values.count)), "round \(round), seed \(seed)")
            }
            let all = try await bounded("round \(round): wait for the flow to end") {
                await recorder.values(atLeast: .max)
            }
            #expect(all == expected, "round \(round), seed \(seed)")
            #expect(recorder.isFinished, "round \(round), seed \(seed)")
            #expect((recorder.failure is FuzzError) == fails, "round \(round), seed \(seed)")
        }
    }
}

private struct FuzzError: Error {}

/// Deterministic generator so the fuzz can be repeated from the printed seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
