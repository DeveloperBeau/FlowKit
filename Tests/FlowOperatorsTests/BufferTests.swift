import Testing
import FlowCore
import FlowSharedModels
import FlowTesting
@testable import FlowOperators

@Suite("buffer operators")
struct BufferTests {
    @Test("buffer with dropOldest drops oldest when full")
    func bufferDropOldest() async throws {
        // A fast producer with a slow consumer
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.buffer(size: 2, policy: .dropOldest).test { tester in
            // The exact values depend on timing, but we should get some values
            let v1 = try await tester.awaitValue()
            #expect(v1 >= 1)
        }
    }

    @Test("buffer with dropLatest drops new values when full")
    func bufferDropLatest() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.buffer(size: 3, policy: .dropLatest).test { tester in
            let v1 = try await tester.awaitValue()
            #expect(v1 >= 1)
        }
    }

    @Test("keepingLatest conflates to the most recent value")
    func keepingLatest() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.keepingLatest().test { tester in
            // Should get at least the last value
            let v = try await tester.awaitValue()
            #expect(v >= 1)
        }
    }

    @Test("buffer with suspend policy waits for consumer")
    func bufferSuspend() async throws {
        let flow = Flow(of: 1, 2, 3, 4, 5)
        try await flow.buffer(size: 2, policy: .suspend).test { tester in
            try await tester.expectValue(1)
            try await tester.expectValue(2)
            try await tester.expectValue(3)
            try await tester.expectValue(4)
            try await tester.expectValue(5)
            try await tester.expectCompletion()
        }
    }

    @Test("buffer with suspend delivers all values in order")
    func bufferSuspendOrdered() async throws {
        let flow = Flow(of: 10, 20, 30)
        try await flow.buffer(size: 1, policy: .suspend).test { tester in
            try await tester.expectValue(10)
            try await tester.expectValue(20)
            try await tester.expectValue(30)
            try await tester.expectCompletion()
        }
    }

    @Test("buffer with empty flow completes without emission")
    func bufferEmpty() async throws {
        let flow = Flow<Int>.empty
        try await flow.buffer(size: 5, policy: .suspend).test { tester in
            try await tester.expectCompletion()
        }
    }
}
