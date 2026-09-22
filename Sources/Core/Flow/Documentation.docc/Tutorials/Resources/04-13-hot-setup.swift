import Testing
import Flow
import FlowTesting

@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("initial state is loggedOut")
    func initialStateIsLoggedOut() async throws {
        let manager = SessionManager()

        // MutableStateFlow replays its current value to each new collector,
        // so the first expectValue call sees the initial state immediately.
        try await TestScope.run { scope in
            let tester = try await scope.test(manager.stateFlow.asFlow())

            // The initial value is emitted as soon as the collector subscribes.
            try await tester.expectValue(.loggedOut)

            // Assertions for transitions continue in the next step.
        }
    }
}
