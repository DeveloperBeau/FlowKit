import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
import FlowTestSupport
import FlowOperators

/// Yields a bounded number of times so a "did not happen" assertion gives the
/// wrong behaviour every scheduling chance to occur before it is checked.
private func settle() async {
    for _ in 0..<100 { await Task.yield() }
}

@Suite("bufferUnbounded")
struct UnboundedBufferTests {
    @Test("a 10k burst against a held consumer is delivered completely, in order")
    func burstFullyDelivered() async {
        let produced = Signal()
        let source = Flow<Int> { collector in
            for value in 0..<10_000 {
                await collector.emit(value)
            }
            produced.fire()
        }

        let received = Mutex<[Int]>([])
        await source.bufferUnbounded().collect { value in
            if value == 0 {
                // Hold the first value until the producer has finished its
                // whole burst, so everything else must sit in the buffer.
                await produced.wait()
            }
            received.withLock { $0.append(value) }
        }
        #expect(produced.hasFired, "an unbounded buffer must never backpressure the producer")
        #expect(received.withLock { $0 } == Array(0..<10_000), "every value delivered, in order")
    }

    @Test("upstream completion mid-drain still delivers the remaining buffered values")
    func completionMidDrainDeliversRemainder() async {
        let produced = Signal()
        let source = Flow<Int> { collector in
            for value in 1...5 {
                await collector.emit(value)
            }
            produced.fire()
        }

        let received = Mutex<[Int]>([])
        await source.bufferUnbounded().collect { value in
            if value == 1 {
                // The upstream completes while the consumer holds the first
                // value; the four still-buffered values must follow before
                // collect returns.
                await produced.wait()
            }
            received.withLock { $0.append(value) }
        }
        #expect(received.withLock { $0 } == [1, 2, 3, 4, 5], "buffered values outlive upstream completion")
    }

    @Test("cancellation mid-drain stops promptly with no delivery after cancel")
    func cancellationMidDrainStops() async {
        let source = Flow<Int> { collector in
            for value in 0..<100 {
                await collector.emit(value)
            }
        }

        let received = Recorder<Void>()
        let stopConsuming = Signal()
        let collector = Task {
            await source.bufferUnbounded().collect { _ in
                received.record(())
                // Slow the drain so cancellation lands mid-buffer.
                if received.count >= 3 { await stopConsuming.wait() }
            }
        }
        await received.wait(atLeast: 3)
        collector.cancel()
        stopConsuming.fire()
        await collector.value

        let countAtCancel = received.count
        #expect(countAtCancel < 100, "cancellation must stop the drain early")
        await settle()
        #expect(received.count == countAtCancel, "no delivery after cancellation")
    }
}
