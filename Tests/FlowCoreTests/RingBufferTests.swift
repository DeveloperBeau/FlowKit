import Testing
@testable import FlowCore

@Suite("RingBuffer")
struct RingBufferTests {
    @Test("empty buffer has zero count")
    func emptyBuffer() {
        let buffer = RingBuffer<Int>(capacity: 5)
        #expect(buffer.count == 0)
        #expect(!buffer.isFull)
        #expect(buffer.elements == [])
    }

    @Test("append under capacity grows count")
    func appendUnderCapacity() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.count == 3)
        #expect(buffer.elements == [1, 2, 3])
    }

    @Test("append when full overwrites oldest")
    func appendWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.isFull)
        buffer.append(4)
        #expect(buffer.count == 3)
        #expect(buffer.elements == [2, 3, 4])
        buffer.append(5)
        #expect(buffer.elements == [3, 4, 5])
    }

    @Test("removeFirst returns and removes oldest")
    func removeFirst() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        #expect(buffer.removeFirst() == 1)
        #expect(buffer.count == 2)
        #expect(buffer.elements == [2, 3])
    }

    @Test("removeFirst on empty returns nil")
    func removeFirstEmpty() {
        var buffer = RingBuffer<Int>(capacity: 5)
        #expect(buffer.removeFirst() == nil)
    }

    @Test("capacity zero behaves as no-op buffer")
    func capacityZero() {
        var buffer = RingBuffer<Int>(capacity: 0)
        buffer.append(1)
        #expect(buffer.count == 0)
        #expect(buffer.elements == [])
    }

    @Test("elements returns values in insertion order after wrap-around")
    func elementsAfterWrapAround() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4) // overwrites 1
        buffer.append(5) // overwrites 2
        #expect(buffer.elements == [3, 4, 5])
    }
}
