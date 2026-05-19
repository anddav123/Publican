// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Publican",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Publican", targets: ["PublicanApp"])
    ],
    targets: [
        .executableTarget(
            name: "PublicanApp"
        )
    ]
)
