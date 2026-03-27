// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "v2rayE",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "v2rayE", targets: ["v2rayE"])
    ],
    targets: [
        .executableTarget(
            name: "v2rayE",
            path: "Sources",
            resources: [
                .process("../Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Network")
            ]
        )
    ]
)
