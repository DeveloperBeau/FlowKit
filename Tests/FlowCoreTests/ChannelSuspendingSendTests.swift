import Testing
import FlowSharedModels
import FlowTesting
@testable import FlowCore

/// Yields a bounded number of times so a "did not happen" assertion gives the
/// wrong behaviour every scheduling chance to occur before it is checked.
private func settle() async {
    for _ in 0..<100 { await Task.yield() }
}

/// Collects the flow to completion into an array. FlowCoreTests cannot use
/// FlowOperators' `toArray`, so this local equivalent keeps the tests direct.
private func collectAll<Element: Sendable>(_ flow: Flow<Element>) async -> [Element] {
    let values = Mutex<[Element]>([])
    await flow.collect { value in values.withLock { $0.append(value) } }
    return values.withLock { $0 }
}

@Suite("ProducerScope.send (suspending)")
struct ChannelSuspendingSendTests {
    // MARK: - Success

    @Test("send suspends the producer while the buffer is full and delivers in order")
    func sendBackpressuresProducer() async {
        // Orderable event log: the producer records after each send returns,
        // the consumer records as it processes. With capacity 1 the second
        // send may only return after the consumer has processed the first value.
        let log = Mutex<[String]>([])
        let allowed = Mutex(0)

        let flow = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .suspend) { scope in
            let first = await scope.send(1)
            log.withLock { $0.append("sent-1:\(first)") }
            let second = await scope.send(2)
            log.withLock { $0.append("sent-2:\(second)") }
            scope.close()
        }

        let collector = Task {
            await flow.collect { value in
                // Hold each value until the test releases it.
                await waitUntil { allowed.withLock { $0 } >= value }
                log.withLock { $0.append("consumed-\(value)") }
            }
        }

        await waitUntil { log.withLock { $0 }.contains("sent-1:enqueued") }
        await settle()
        #expect(
            !log.withLock { $0 }.contains { $0.hasPrefix("sent-2") },
            "with capacity 1 and an unconsumed value, the second send must stay suspended"
        )

        allowed.withLock { $0 = 1 }
        await waitUntil { log.withLock { $0 }.contains { $0.hasPrefix("sent-2") } }
        let entries = log.withLock { $0 }
        let consumedFirst = entries.firstIndex(of: "consumed-1")
        let sentSecond = entries.firstIndex(of: "sent-2:enqueued")
        #expect(consumedFirst != nil && sentSecond != nil && consumedFirst! < sentSecond!,
                "the suspended send may only resume after the consumer processes the first value")

        allowed.withLock { $0 = 2 }
        await collector.value
        #expect(log.withLock { $0 }.contains("consumed-2"), "all values delivered in order")
    }

    @Test("send does not suspend under dropping policies or an unbounded channel")
    func sendDoesNotSuspendWithoutSuspendPolicy() async {
        // No consumer processes anything until the producer has finished all
        // sends, so any send-side suspension would deadlock-fail the test.
        let done = Mutex(false)
        let dropping = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .dropOldest) { scope in
            for value in 1...5 { await scope.send(value) }
            done.withLock { $0 = true }
            scope.close()
        }
        _ = await collectAll(dropping)
        #expect(done.withLock { $0 })

        let doneUnbounded = Mutex(false)
        let unbounded = Flow<Int>.channelFlow(bufferCapacity: 0, onBufferOverflow: .suspend) { scope in
            for value in 1...100 { await scope.send(value) }
            doneUnbounded.withLock { $0 = true }
            scope.close()
        }
        let values = await collectAll(unbounded)
        #expect(doneUnbounded.withLock { $0 })
        #expect(values == Array(1...100))
    }

    // MARK: - Misuse

    @Test("send after close returns .closed and delivers nothing")
    func sendAfterClose() async {
        let afterCloseResult = Mutex<ChannelSendResult?>(nil)
        let flow = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .suspend) { scope in
            await scope.send(1)
            scope.close()
            let result = await scope.send(2)
            afterCloseResult.withLock { $0 = result }
        }
        let received = await collectAll(flow)
        #expect(received == [1])
        await waitUntil { afterCloseResult.withLock { $0 } != nil }
        #expect(afterCloseResult.withLock { $0 } == .closed, "send after close is rejected, not buffered")
    }

    // MARK: - Fuzz / adversarial

    @Test("cancellation racing a suspended send unblocks the producer with .closed")
    func cancellationUnblocksSuspendedSend() async {
        let producerExited = Mutex(false)
        let suspendedResult = Mutex<ChannelSendResult?>(nil)
        let firstDelivered = Mutex(false)

        let flow = Flow<Int>.channelFlow(bufferCapacity: 1, onBufferOverflow: .suspend) { scope in
            await scope.send(1)
            // The consumer never frees the slot, so this send parks until the
            // collector is cancelled.
            let result = await scope.send(2)
            suspendedResult.withLock { $0 = result }
            producerExited.withLock { $0 = true }
        }

        let deliveredAfterTermination = Mutex(false)
        let collector = Task {
            await flow.collect { value in
                if value == 1 {
                    firstDelivered.withLock { $0 = true }
                    // Park the consumer until cancellation tears it down.
                    while !Task.isCancelled { await waitUntil { Task.isCancelled } }
                } else {
                    deliveredAfterTermination.withLock { $0 = true }
                }
            }
        }
        await waitUntil { firstDelivered.withLock { $0 } }

        collector.cancel()
        await waitUntil { producerExited.withLock { $0 } }
        #expect(producerExited.withLock { $0 }, "cancellation must unblock the suspended producer")
        #expect(suspendedResult.withLock { $0 } == .closed, "a send interrupted by teardown reports .closed")

        await collector.value
        await settle()
        #expect(!deliveredAfterTermination.withLock { $0 }, "no value may be delivered after termination")
    }

    @Test("send storm racing cancellation delivers nothing after termination and never wedges")
    func sendStormRacingCancellation() async {
        for _ in 0..<25 {
            let producerExited = Mutex(false)
            let received = Mutex(0)

            let flow = Flow<Int>.channelFlow(bufferCapacity: 2, onBufferOverflow: .suspend) { scope in
                var sent = 0
                while sent < 1_000 {
                    let result = await scope.send(sent)
                    if result == .closed { break }
                    sent += 1
                }
                producerExited.withLock { $0 = true }
            }

            let collector = Task {
                await flow.collect { _ in
                    received.withLock { $0 += 1 }
                }
            }
            await waitUntil { received.withLock { $0 } >= 1 }
            collector.cancel()
            await collector.value

            // The producer must always exit: either it finished its sends or
            // a send observed the closed channel; a leaked continuation would
            // hang here and trip the waitUntil timeout.
            await waitUntil { producerExited.withLock { $0 } }
            #expect(producerExited.withLock { $0 }, "producer must exit exactly once per teardown")

            let countAtTermination = received.withLock { $0 }
            await settle()
            #expect(received.withLock { $0 } == countAtTermination, "no delivery after termination")
        }
    }
}
