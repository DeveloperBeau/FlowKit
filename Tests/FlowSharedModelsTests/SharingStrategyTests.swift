import Testing
import Foundation
@testable import FlowSharedModels

@Suite("SharingStrategy")
struct SharingStrategyTests {
    @Test("eager strategy exists")
    func eagerCase() {
        let strategy: SharingStrategy = .eager
        if case .eager = strategy { } else {
            Issue.record("expected .eager")
        }
    }

    @Test("lazy strategy exists")
    func lazyCase() {
        let strategy: SharingStrategy = .lazy
        if case .lazy = strategy { } else {
            Issue.record("expected .lazy")
        }
    }

    @Test("whileSubscribed with default durations")
    func whileSubscribedDefaults() {
        let strategy: SharingStrategy = .whileSubscribed()
        guard case .whileSubscribed(let stopTimeout, let replayExpiration) = strategy else {
            Issue.record("expected .whileSubscribed")
            return
        }
        #expect(stopTimeout == .zero)
        #expect(replayExpiration == .zero)
    }

    @Test("whileSubscribed with custom durations")
    func whileSubscribedCustom() {
        let strategy: SharingStrategy = .whileSubscribed(
            stopTimeout: .seconds(5),
            replayExpiration: .seconds(30)
        )
        guard case .whileSubscribed(let stopTimeout, let replayExpiration) = strategy else {
            Issue.record("expected .whileSubscribed")
            return
        }
        #expect(stopTimeout == .seconds(5))
        #expect(replayExpiration == .seconds(30))
    }
}
