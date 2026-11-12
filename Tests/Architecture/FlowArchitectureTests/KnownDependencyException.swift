/// An import the architecture test allows until the manifest catches up.
///
/// Each entry is one file. The import is allowed by the ring rules, and
/// Package.swift does not declare it. A ring violation uses
/// `ringViolation` instead, and a new import that is not listed here fails
/// the suite.
struct KnownDependencyException: Equatable, Sendable {
    /// Which kind of break the entry records.
    enum Kind: Sendable, Equatable {
        /// The import points inward, or it is test support. The manifest omits it.
        case undeclaredImport
        /// The dependency points outward or sideways and is left in place on purpose.
        case ringViolation

        func matches(_ rule: DependencyViolation.Rule) -> Bool {
            switch self {
            case .undeclaredImport:
                rule == .undeclaredImport
            case .ringViolation:
                rule == .outwardDependency || rule == .sidewaysDependency
            }
        }
    }

    var target: String
    var importedModule: String
    var file: String
    var line: Int
    var kind: Kind
    var reason: String

    private static let flowCoreTestsUsesFlowSharedModels = "The tests use Mutex and the other shared types, and Package.swift does not list FlowSharedModels."
    private static let flowCoreTestsUsesFlowTestingCore = "The tests use TestScope and the testers, and Package.swift lists FlowTesting rather than FlowTestingCore."
    private static let flowHotStreamsTestsUsesFlowCore = "The tests build cold flows, and Package.swift does not list FlowCore."
    private static let flowHotStreamsTestsUsesFlowSharedModels = "The tests use shared model types, and Package.swift does not list FlowSharedModels."
    private static let flowHotStreamsTestsUsesFlowTestClock = "The tests advance a TestClock, and Package.swift does not list FlowTestClock."
    private static let flowHotStreamsTestsUsesFlowTestingCore = "The tests use the testing core, and Package.swift does not list FlowTestingCore."
    private static let flowOperatorsUsesFlowSharedModels = "Operators use buffer and sharing types from FlowSharedModels, and Package.swift only lists FlowCore and AsyncAlgorithms."
    private static let flowOperatorsTestsUsesFlowCore = "The tests build Flow values, and Package.swift does not list FlowCore."
    private static let flowOperatorsTestsUsesFlowSharedModels = "The tests use shared model types, and Package.swift does not list FlowSharedModels."
    private static let flowTestClockTestsUsesFlowSharedModels = "The sleeper test uses a shared type, and Package.swift does not list FlowSharedModels."
    private static let flowTestSupportUsesFlowCore = "ProbeScope owns a FlowScope, and Package.swift does not list FlowCore."
    private static let flowTestSupportUsesFlowTestingCore = "ProbeScope returns a FlowReader, and Package.swift does not list FlowTestingCore."
    private static let flowTestingUsesFlowSharedModels = "The umbrella re-exports FlowSharedModels so callers see FlowTestError, and Package.swift does not list it."
    private static let flowTestingCoreUsesFlowCore = "Testers and TestScope use Flow and ThrowingFlow, and Package.swift lists the Flow umbrella rather than FlowCore."
    private static let flowTestingCoreUsesFlowSharedModels = "These files throw FlowTestError, and Package.swift does not list FlowSharedModels."
    private static let flowTestingCoreTestsUsesFlowCore = "The tests build Flow values, and Package.swift does not list FlowCore."
    private static let flowTestingCoreTestsUsesFlowHotStreams = "FlowReaderTests builds a hot flow, and Package.swift does not list FlowHotStreams."
    private static let flowTestingCoreTestsUsesFlowSharedModels = "The tests use FlowTestError and Mutex, and Package.swift does not list FlowSharedModels."
    private static let flowTestingCoreTestsUsesFlowTestClock = "The tests drive a TestClock, and Package.swift does not list FlowTestClock."
    private static let flowTestingPublicAPITestsUsesFlow = "The reachability test builds a Flow, and Package.swift only lists FlowTesting."
    private static let flowUIKitBridgeUsesFlowOperators = "The bridge calls onEach, and Package.swift only lists FlowCore and FlowHotStreams."
    private static let flowUITestsUsesFlowCore = "The UI tests build cold flows, and Package.swift does not list FlowCore."
    private static let flowUITestsUsesFlowHotStreams = "The bridge tests build a state flow, and Package.swift does not list FlowHotStreams."
    private static let flowUITestsUsesFlowSharedModels = "ViewExtensionsTests uses a shared type, and Package.swift does not list FlowSharedModels."
    private static let flowUITestsUsesFlowSwiftUI = "The test imports the SwiftUI bridge it exercises, and Package.swift lists the FlowUI umbrella instead."
    private static let flowUITestsUsesFlowUIKitBridge = "The test imports the UIKit and AppKit bridge it exercises, and Package.swift lists the FlowUI umbrella instead."

    static let all: [KnownDependencyException] = [
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/ChannelFlowTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/ChannelSuspendingSendTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/CollectorTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/FlowBuildersTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/FlowLaunchTests.swift", 3, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/FlowScopeTests.swift", 4, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/FlowTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/Flow/MemoryLeakTests.swift", 4, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/ThrowingFlow/ThrowingCollectorTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/ThrowingFlow/ThrowingFlowBuildersTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowSharedModels", "Tests/Core/FlowCoreTests/ThrowingFlow/ThrowingFlowTests.swift", 2, flowCoreTestsUsesFlowSharedModels),
        entry("FlowCoreTests", "FlowTestingCore", "Tests/Core/FlowCoreTests/Flow/FlowLaunchTests.swift", 4, flowCoreTestsUsesFlowTestingCore),
        entry("FlowCoreTests", "FlowTestingCore", "Tests/Core/FlowCoreTests/Flow/FlowScopeTests.swift", 5, flowCoreTestsUsesFlowTestingCore),
        entry("FlowCoreTests", "FlowTestingCore", "Tests/Core/FlowCoreTests/Flow/MemoryLeakTests.swift", 5, flowCoreTestsUsesFlowTestingCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/HotStreamHardeningTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/PerformanceTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/ReadOnlyViewTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/AsSharedFlowTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/ReplayExpirationTests.swift", 4, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharedFlowBackpressureTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharedFlowTests.swift", 3, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharingCoordinatorTests.swift", 4, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SharingTeardownTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/StateFlow/AsStateFlowTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowAtomicsTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowSubscriptionCountTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowSyncValueTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/SubscriberWaiterTests.swift", 2, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowCore", "Tests/Core/FlowHotStreamsTests/WhileSubscribedDefaultTests.swift", 3, flowHotStreamsTestsUsesFlowCore),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/HotStreamHardeningTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/PerformanceTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/ReadOnlyViewTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharedFlow/AsSharedFlowTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharedFlow/ReplayExpirationTests.swift", 5, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharedFlowBackpressureTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharedFlowTests.swift", 4, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharingCoordinatorTests.swift", 5, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SharingTeardownTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/StateFlow/AsStateFlowTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowSubscriptionCountTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowSyncValueTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/StateFlow/StateFlowTests.swift", 5, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/SubscriberWaiterTests.swift", 3, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowSharedModels", "Tests/Core/FlowHotStreamsTests/WhileSubscribedDefaultTests.swift", 4, flowHotStreamsTestsUsesFlowSharedModels),
        entry("FlowHotStreamsTests", "FlowTestClock", "Tests/Core/FlowHotStreamsTests/SharedFlow/ReplayExpirationTests.swift", 6, flowHotStreamsTestsUsesFlowTestClock),
        entry("FlowHotStreamsTests", "FlowTestClock", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharingCoordinatorTests.swift", 6, flowHotStreamsTestsUsesFlowTestClock),
        entry("FlowHotStreamsTests", "FlowTestClock", "Tests/Core/FlowHotStreamsTests/WhileSubscribedDefaultTests.swift", 5, flowHotStreamsTestsUsesFlowTestClock),
        entry("FlowHotStreamsTests", "FlowTestingCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/ReplayExpirationTests.swift", 7, flowHotStreamsTestsUsesFlowTestingCore),
        entry("FlowHotStreamsTests", "FlowTestingCore", "Tests/Core/FlowHotStreamsTests/SharedFlow/SharingCoordinatorTests.swift", 7, flowHotStreamsTestsUsesFlowTestingCore),
        entry("FlowHotStreamsTests", "FlowTestingCore", "Tests/Core/FlowHotStreamsTests/WhileSubscribedDefaultTests.swift", 6, flowHotStreamsTestsUsesFlowTestingCore),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/Buffering.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/Lifecycle.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/RateLimiting.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/Terminal.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/Timeout.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperators", "FlowSharedModels", "Sources/Core/FlowOperators/Transform.swift", 2, flowOperatorsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/AsyncSequenceBridge/AsyncSequenceInteropTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/AsyncSequenceBridge/AsyncStreamBridgeTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Buffering/BufferTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Buffering/UnboundedBufferTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/CombineLatestArityTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/CombineLatestTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/CombineLatestWideArityTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/MergeTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/ThrowingFlowCombiningTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Combining/ZipTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/ErrorHandling/CatchTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/ErrorHandling/RetryTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Flattening/FlatMapLatestTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Flattening/FlatMapTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Flattening/MapLatestTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Lifecycle/OnCompletionTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Lifecycle/OnEachTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Lifecycle/OnStartTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/RateLimiting/DebounceTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/RateLimiting/RemoveDuplicatesTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/RateLimiting/SampleTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/RateLimiting/ThrottleTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/RateLimiting/ThrowingFlowRateLimitingTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Terminal/ParityTerminalTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Terminal/ShortCircuitTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Terminal/TerminalOperatorTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/ThrowingFlowOperatorTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/TimeoutTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/CompactMapTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/DropFirstTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/FilterIsInstanceTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/FilterTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/MapTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/ParityTransformTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/PrefixTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/ScanTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowCore", "Tests/Core/FlowOperatorsTests/Transform/TransformOperatorTests.swift", 2, flowOperatorsTestsUsesFlowCore),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/AsyncSequenceBridge/AsyncSequenceInteropTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/AsyncSequenceBridge/AsyncStreamBridgeTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Buffering/BufferTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Buffering/UnboundedBufferTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Combining/CombineLatestArityTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Combining/CombineLatestWideArityTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/ErrorHandling/CatchTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/ErrorHandling/RetryTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Flattening/FlatMapLatestTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Flattening/FlatMapTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Flattening/MapLatestTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Lifecycle/OnCompletionTests.swift", 5, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Lifecycle/OnEachTests.swift", 5, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Lifecycle/OnStartTests.swift", 5, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/RateLimiting/DebounceTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/RateLimiting/SampleTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/RateLimiting/ThrottleTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Terminal/ParityTerminalTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Terminal/ShortCircuitTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Terminal/TerminalOperatorTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/ThrowingFlowOperatorTests.swift", 5, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/TimeoutTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowOperatorsTests", "FlowSharedModels", "Tests/Core/FlowOperatorsTests/Transform/ParityTransformTests.swift", 3, flowOperatorsTestsUsesFlowSharedModels),
        entry("FlowTestClockTests", "FlowSharedModels", "Tests/Testing/FlowTestClockTests/TestClockSleeperWaiterTests.swift", 3, flowTestClockTestsUsesFlowSharedModels),
        entry("FlowTestSupport", "FlowCore", "Tests/Support/FlowTestSupport/ProbeScope.swift", 1, flowTestSupportUsesFlowCore),
        entry("FlowTestSupport", "FlowTestingCore", "Tests/Support/FlowTestSupport/ProbeScope.swift", 3, flowTestSupportUsesFlowTestingCore),
        entry("FlowTesting", "FlowSharedModels", "Sources/Testing/FlowTesting/FlowTesting.swift", 6, flowTestingUsesFlowSharedModels),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/TestScope.swift", 2, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/Testers/FlowProbe.swift", 2, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/Testers/FlowReader.swift", 3, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/Testers/FlowTestExtensions.swift", 2, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/Testers/FlowTester.swift", 4, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowCore", "Sources/Testing/FlowTestingCore/Testers/ThrowingFlowTester.swift", 4, flowTestingCoreUsesFlowCore),
        entry("FlowTestingCore", "FlowSharedModels", "Sources/Testing/FlowTestingCore/Testers/FlowTester.swift", 3, flowTestingCoreUsesFlowSharedModels),
        entry("FlowTestingCore", "FlowSharedModels", "Sources/Testing/FlowTestingCore/Testers/FlowTesterBase.swift", 3, flowTestingCoreUsesFlowSharedModels),
        entry("FlowTestingCore", "FlowSharedModels", "Sources/Testing/FlowTestingCore/Testers/ThrowingFlowTester.swift", 3, flowTestingCoreUsesFlowSharedModels),
        entry("FlowTestingCore", "FlowSharedModels", "Sources/Testing/FlowTestingCore/TimeoutHelpers.swift", 2, flowTestingCoreUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/TestScopeTests.swift", 2, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/Testers/FlowProbeTests.swift", 2, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/Testers/FlowReaderTests.swift", 3, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/Testers/FlowTestExtensionsTests.swift", 3, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/Testers/FlowTesterTests.swift", 3, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowCore", "Tests/Testing/FlowTestingCoreTests/Testers/ThrowingFlowTesterTests.swift", 3, flowTestingCoreTestsUsesFlowCore),
        entry("FlowTestingCoreTests", "FlowHotStreams", "Tests/Testing/FlowTestingCoreTests/Testers/FlowReaderTests.swift", 4, flowTestingCoreTestsUsesFlowHotStreams),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/TestScopeTests.swift", 3, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/Testers/FlowReaderTests.swift", 5, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/Testers/FlowTestExtensionsTests.swift", 4, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/Testers/FlowTesterTests.swift", 4, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/Testers/ThrowingFlowTesterTests.swift", 4, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/TimeoutHelpersTests.swift", 3, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowSharedModels", "Tests/Testing/FlowTestingCoreTests/WaitUntilTests.swift", 3, flowTestingCoreTestsUsesFlowSharedModels),
        entry("FlowTestingCoreTests", "FlowTestClock", "Tests/Testing/FlowTestingCoreTests/TestScopeTests.swift", 4, flowTestingCoreTestsUsesFlowTestClock),
        entry("FlowTestingCoreTests", "FlowTestClock", "Tests/Testing/FlowTestingCoreTests/Testers/FlowTestExtensionsTests.swift", 5, flowTestingCoreTestsUsesFlowTestClock),
        entry("FlowTestingCoreTests", "FlowTestClock", "Tests/Testing/FlowTestingCoreTests/TimeoutHelpersTests.swift", 4, flowTestingCoreTestsUsesFlowTestClock),
        entry("FlowTestingCoreTests", "FlowTestClock", "Tests/Testing/FlowTestingCoreTests/WaitUntilTests.swift", 4, flowTestingCoreTestsUsesFlowTestClock),
        entry("FlowTestingPublicAPITests", "Flow", "Tests/Testing/FlowTestingPublicAPITests/FlowTestingReachabilityTests.swift", 2, flowTestingPublicAPITestsUsesFlow),
        entry("FlowUIKitBridge", "FlowOperators", "Sources/UI/FlowUIKitBridge/AppKitExtensions.swift", 6, flowUIKitBridgeUsesFlowOperators),
        entry("FlowUIKitBridge", "FlowOperators", "Sources/UI/FlowUIKitBridge/UIViewControllerExtensions.swift", 6, flowUIKitBridgeUsesFlowOperators),
        entry("FlowUITests", "FlowCore", "Tests/UI/FlowUITests/AppKitBridgeTests.swift", 4, flowUITestsUsesFlowCore),
        entry("FlowUITests", "FlowCore", "Tests/UI/FlowUITests/FlowObservingTests.swift", 4, flowUITestsUsesFlowCore),
        entry("FlowUITests", "FlowCore", "Tests/UI/FlowUITests/ObservedStateFlowTests.swift", 5, flowUITestsUsesFlowCore),
        entry("FlowUITests", "FlowCore", "Tests/UI/FlowUITests/UIKitBridgeTests.swift", 4, flowUITestsUsesFlowCore),
        entry("FlowUITests", "FlowCore", "Tests/UI/FlowUITests/ViewExtensionsTests.swift", 4, flowUITestsUsesFlowCore),
        entry("FlowUITests", "FlowHotStreams", "Tests/UI/FlowUITests/AppKitBridgeTests.swift", 5, flowUITestsUsesFlowHotStreams),
        entry("FlowUITests", "FlowHotStreams", "Tests/UI/FlowUITests/ObservedStateFlowTests.swift", 6, flowUITestsUsesFlowHotStreams),
        entry("FlowUITests", "FlowHotStreams", "Tests/UI/FlowUITests/UIKitBridgeTests.swift", 5, flowUITestsUsesFlowHotStreams),
        entry("FlowUITests", "FlowSharedModels", "Tests/UI/FlowUITests/ViewExtensionsTests.swift", 5, flowUITestsUsesFlowSharedModels),
        entry("FlowUITests", "FlowSwiftUI", "Tests/UI/FlowUITests/FlowObservingTests.swift", 7, flowUITestsUsesFlowSwiftUI),
        entry("FlowUITests", "FlowSwiftUI", "Tests/UI/FlowUITests/ObservedStateFlowTests.swift", 9, flowUITestsUsesFlowSwiftUI),
        entry("FlowUITests", "FlowSwiftUI", "Tests/UI/FlowUITests/ViewExtensionsTests.swift", 6, flowUITestsUsesFlowSwiftUI),
        entry("FlowUITests", "FlowUIKitBridge", "Tests/UI/FlowUITests/AppKitBridgeTests.swift", 6, flowUITestsUsesFlowUIKitBridge),
        entry("FlowUITests", "FlowUIKitBridge", "Tests/UI/FlowUITests/UIKitBridgeTests.swift", 6, flowUITestsUsesFlowUIKitBridge),
    ]

    private static func entry(
        _ target: String,
        _ importedModule: String,
        _ file: String,
        _ line: Int,
        _ reason: String,
        kind: Kind = .undeclaredImport
    ) -> KnownDependencyException {
        KnownDependencyException(
            target: target,
            importedModule: importedModule,
            file: file,
            line: line,
            kind: kind,
            reason: reason
        )
    }
}
