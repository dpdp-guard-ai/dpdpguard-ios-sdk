// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DPDPGuardConsent",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "DPDPGuardConsent", targets: ["DPDPGuardConsent"])
    ],
    targets: [
        .target(name: "DPDPGuardConsent"),
        .testTarget(
            name: "DPDPGuardConsentTests",
            dependencies: ["DPDPGuardConsent"],
            resources: [.copy("Resources/audit-hash-vectors.json")]
        )
    ]
)
