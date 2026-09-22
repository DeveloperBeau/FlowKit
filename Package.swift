// swift-tools-version: 6.3
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "FlowKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Flow", targets: ["Flow"]),
        .library(name: "FlowTesting", targets: ["FlowTesting"]),
        .library(name: "FlowUI", targets: ["FlowUI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-async-algorithms",
            exact: "1.1.3"
        ),
        .package(
            url: "https://github.com/apple/swift-docc-plugin",
            exact: "1.4.6"
        ),
        .package(
            url: "https://github.com/apple/swift-crypto",
            exact: "4.5.1"
        )
    ],
    targets: [
        // ─────────── Shared base (no dependencies) ───────────

        .target(
            name: "FlowSharedModels",
            dependencies: [],
            path: "Sources/Shared/FlowSharedModels",
            swiftSettings: strictSettings
        ),

        // ─────────── Flow library ───────────

        .target(
            name: "FlowCore",
            dependencies: ["FlowSharedModels"],
            path: "Sources/Core/FlowCore",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowOperators",
            dependencies: [
                "FlowCore",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            path: "Sources/Core/FlowOperators",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowHotStreams",
            dependencies: ["FlowSharedModels", "FlowCore", "FlowOperators"],
            path: "Sources/Core/FlowHotStreams",
            swiftSettings: strictSettings
        ),
        .target(
            name: "Flow",
            dependencies: [
                "FlowSharedModels",
                "FlowCore",
                "FlowOperators",
                "FlowHotStreams"
            ],
            path: "Sources/Core/Flow",
            swiftSettings: strictSettings
        ),

        // ─────────── FlowUI library ───────────

        .target(
            name: "FlowSwiftUI",
            dependencies: ["FlowSharedModels", "FlowCore", "FlowHotStreams", "Flow"],
            path: "Sources/UI/FlowSwiftUI",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowUIKitBridge",
            dependencies: ["FlowCore", "FlowHotStreams"],
            path: "Sources/UI/FlowUIKitBridge",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowUI",
            dependencies: ["FlowSwiftUI", "FlowUIKitBridge", "Flow"],
            path: "Sources/UI/FlowUI",
            swiftSettings: strictSettings
        ),

        // ─────────── FlowTesting library ───────────

        .target(
            name: "FlowTestClock",
            dependencies: ["FlowSharedModels"],
            path: "Sources/Testing/FlowTestClock",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowTestingCore",
            dependencies: ["Flow", "FlowTestClock"],
            path: "Sources/Testing/FlowTestingCore",
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowTesting",
            dependencies: ["FlowTestClock", "FlowTestingCore"],
            path: "Sources/Testing/FlowTesting",
            swiftSettings: strictSettings
        ),

        // ─────────── Test targets ───────────

        .testTarget(
            name: "FlowSharedModelsTests",
            dependencies: ["FlowSharedModels"],
            path: "Tests/Shared/FlowSharedModelsTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore", "FlowTesting"],
            path: "Tests/Core/FlowCoreTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowOperatorsTests",
            dependencies: ["FlowOperators", "FlowHotStreams", "FlowTesting", "FlowTestClock"],
            path: "Tests/Core/FlowOperatorsTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowHotStreamsTests",
            dependencies: ["FlowHotStreams", "FlowTesting"],
            path: "Tests/Core/FlowHotStreamsTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestClockTests",
            dependencies: ["FlowTestClock", "FlowTestingCore"],
            path: "Tests/Testing/FlowTestClockTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestingCoreTests",
            dependencies: ["FlowTestingCore"],
            path: "Tests/Testing/FlowTestingCoreTests",
            swiftSettings: strictSettings
        ),

        .testTarget(
            name: "FlowSimulationTests",
            dependencies: [
                "Flow",
                "FlowTesting",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Tests/Core/FlowSimulationTests",
            swiftSettings: strictSettings
        ),

        // Public API reachability tests — umbrella-only imports

        .testTarget(
            name: "FlowPublicAPITests",
            dependencies: ["Flow"],
            path: "Tests/Core/FlowPublicAPITests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestingPublicAPITests",
            dependencies: ["FlowTesting"],
            path: "Tests/Testing/FlowTestingPublicAPITests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowUITests",
            dependencies: ["FlowUI", "FlowTesting"],
            path: "Tests/UI/FlowUITests",
            swiftSettings: strictSettings
        )
    ]
)
