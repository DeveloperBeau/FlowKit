import Testing
import Foundation
@testable import FlowHotStreams

@Suite("MulticastSubscription")
struct MulticastSubscriptionTests {
    @Test("creating a subscription returns a unique ID and stream")
    func subscriptionCreation() async {
        let subscription = MulticastSubscription<Int>()
        let (id1, _) = await subscription.makeSubscription()
        let (id2, _) = await subscription.makeSubscription()
        #expect(id1 != id2)
    }

    @Test("deliver sends to all active subscribers")
    func deliverSendsToAll() async {
        let subscription = MulticastSubscription<Int>()
        let (_, stream1) = await subscription.makeSubscription()
        let (_, stream2) = await subscription.makeSubscription()

        await subscription.deliver(42)

        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()
        let v1 = await iterator1.next()
        let v2 = await iterator2.next()
        #expect(v1 == 42)
        #expect(v2 == 42)
    }

    @Test("unsubscribe removes a subscriber so deliver skips it")
    func unsubscribeRemoves() async {
        let subscription = MulticastSubscription<Int>()
        let (id1, _) = await subscription.makeSubscription()
        let (_, stream2) = await subscription.makeSubscription()

        await subscription.unsubscribe(id: id1)
        await subscription.deliver(7)

        var iter = stream2.makeAsyncIterator()
        let v = await iter.next()
        #expect(v == 7)
        #expect(await subscription.subscriberCount == 1)
    }

    @Test("subscriberCount reflects current state")
    func subscriberCount() async {
        let subscription = MulticastSubscription<Int>()
        #expect(await subscription.subscriberCount == 0)
        let (id1, _) = await subscription.makeSubscription()
        #expect(await subscription.subscriberCount == 1)
        let (id2, _) = await subscription.makeSubscription()
        #expect(await subscription.subscriberCount == 2)
        await subscription.unsubscribe(id: id1)
        #expect(await subscription.subscriberCount == 1)
        await subscription.unsubscribe(id: id2)
        #expect(await subscription.subscriberCount == 0)
    }

    @Test("finishAll finishes and removes all subscribers")
    func finishAllClearsSubscribers() async {
        let subscription = MulticastSubscription<Int>()
        let (_, _) = await subscription.makeSubscription()
        let (_, _) = await subscription.makeSubscription()
        #expect(await subscription.subscriberCount == 2)

        await subscription.finishAll()
        #expect(await subscription.subscriberCount == 0)
    }

    @Test("finishAll ends each stream after the values it had buffered")
    func finishAllKeepsBufferedValues() async {
        let subscription = MulticastSubscription<Int>()
        let (_, stream) = await subscription.makeSubscription()
        await subscription.deliver(1)
        await subscription.deliver(2)

        await subscription.finishAll()

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        #expect(await iterator.next() == 2)
        #expect(await iterator.next() == nil)
    }

    @Test("deliver reports whether the subscription is still open")
    func deliverReportsClosed() async {
        let subscription = MulticastSubscription<Int>()
        #expect(await subscription.deliver(1))

        await subscription.finishAll()

        #expect(!(await subscription.deliver(2)))
    }

    @Test("a subscription made after finishAll is finished and not counted")
    func subscriptionAfterFinishAll() async {
        let subscription = MulticastSubscription<Int>()
        await subscription.finishAll()

        let (id, stream) = await subscription.makeSubscription()
        await subscription.deliver(1, to: id)

        #expect(await subscription.subscriberCount == 0)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
