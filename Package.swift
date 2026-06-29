// swift-tools-version:6.0
import PackageDescription

// Expys data SDK for Swift. SwiftPM, async/await, URLSession, zero external
// dependencies. Source lives in the monorepo (packages/sdk-swift); releases are
// mirrored to the public `expys-swift` repo so SwiftPM can resolve it by git URL
// + semver tag.
//
// Built in the Swift 6 language mode with complete data-race checking
// (the default under tools-version 6.0; pinned explicitly per target so the
// "Ready for Swift 6" guarantee is intentional, not incidental).
let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

// Each reference example is its own executable target so it is independently
// runnable (`swift run <Name>Example`) and compile-checked by `swift build` / CI.
// None is a product; consumers only get the ExpysSDK library.
let exampleNames = [
  "BrowseRedeem",
  "Pagination",
  "ErrorHandling",
  "TokenRefresh",
  "Environments",
  "Idempotency",
  "Configuration",
  "EligibilityWallet",
  "RedemptionsList",
  "Conversations",
  "StreamMessages",
  "ServerMode",
]

let exampleTargets: [Target] = exampleNames.map { name in
  .executableTarget(
    name: "\(name)Example",
    dependencies: ["ExpysSDK"],
    path: "Examples/\(name)",
    swiftSettings: swift6
  )
}

let package = Package(
  name: "ExpysSDK",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "ExpysSDK", targets: ["ExpysSDK"]),
  ],
  targets: [
    .target(name: "ExpysSDK", swiftSettings: swift6),
    .testTarget(
      name: "ExpysSDKTests",
      dependencies: ["ExpysSDK"],
      swiftSettings: swift6
    ),
  ] + exampleTargets
)

// The Swift-DocC plugin is a build-tool dependency used only to generate the DocC
// reference (locally, in CI, and on the Swift Package Index). It is added only when
// EXPYS_BUILD_DOCS is set so that consumers of ExpysSDK keep a zero-dependency graph.
//   EXPYS_BUILD_DOCS=1 swift package generate-documentation --target ExpysSDK
if Context.environment["EXPYS_BUILD_DOCS"] != nil {
  package.dependencies += [
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
  ]
}
