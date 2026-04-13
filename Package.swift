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
        )
    ],
    targets: [
        // ─────────── Shared base (no dependencies) ───────────

        .target(
            name: "FlowSharedModels",
            dependencies: [],
            swiftSettings: strictSettings
        ),

        // ─────────── Flow library ───────────

        .target(
            name: "FlowCore",
            dependencies: ["FlowSharedModels"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowOperators",
            dependencies: [
                "FlowCore",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowHotStreams",
            dependencies: ["FlowSharedModels", "FlowCore", "FlowOperators"],
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
            swiftSettings: strictSettings
        ),

        // ─────────── FlowUI library ───────────

        .target(
            name: "FlowSwiftUI",
            dependencies: ["FlowCore", "FlowHotStreams", "Flow"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowUIKitBridge",
            dependencies: ["FlowCore", "FlowHotStreams"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowUI",
            dependencies: ["FlowSwiftUI", "FlowUIKitBridge", "Flow"],
            swiftSettings: strictSettings
        ),

        // ─────────── FlowTesting library ───────────

        .target(
            name: "FlowTestClock",
            dependencies: ["FlowSharedModels"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowTestingCore",
            dependencies: ["Flow", "FlowTestClock"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FlowTesting",
            dependencies: ["FlowTestClock", "FlowTestingCore"],
            swiftSettings: strictSettings
        ),

        // ─────────── Test targets ───────────

        .testTarget(
            name: "FlowSharedModelsTests",
            dependencies: ["FlowSharedModels"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore", "FlowTesting"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowOperatorsTests",
            dependencies: ["FlowOperators", "FlowHotStreams", "FlowTesting", "FlowTestClock"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowHotStreamsTests",
            dependencies: ["FlowHotStreams", "FlowTesting"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestClockTests",
            dependencies: ["FlowTestClock"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestingCoreTests",
            dependencies: ["FlowTestingCore"],
            swiftSettings: strictSettings
        ),

        // Public API reachability tests — umbrella-only imports

        .testTarget(
            name: "FlowPublicAPITests",
            dependencies: ["Flow"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowTestingPublicAPITests",
            dependencies: ["FlowTesting"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FlowUITests",
            dependencies: ["FlowUI", "FlowTesting"],
            swiftSettings: strictSettings
        )
    ]
)
