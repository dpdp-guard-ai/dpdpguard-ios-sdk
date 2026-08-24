// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DPDPGuardConsent",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [
        .library(name: "DPDPGuardConsent", targets: ["DPDPGuardConsent"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "DPDPGuardConsentAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/DPDPGuardConsentAPI",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "DPDPGuardConsent",
            dependencies: [
                "DPDPGuardConsentAPI",
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "DPDPGuardConsentTests",
            dependencies: ["DPDPGuardConsent"],
            resources: [
                .copy("Resources/audit-hash-vectors.json"),
                .copy("Resources/error-catalog.json"),
                .copy("Resources/capture-artifact-vectors.json")
            ]
        )
    ]
)
