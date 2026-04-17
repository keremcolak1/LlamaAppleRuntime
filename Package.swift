// swift-tools-version: 6.2

import PackageDescription

// This manifest is intended for the future standalone LlamaAppleRuntime repository.
// Replace the owner, tag, and checksum after publishing the first real artifact.

let llamaAppleVersion = "0.1.0"
let llamaAppleURL = "https://github.com/OWNER/LlamaAppleRuntime/releases/download/\(llamaAppleVersion)/LlamaApple.xcframework.zip"
let llamaAppleChecksum = "0000000000000000000000000000000000000000000000000000000000000000"

let package = Package(
    name: "LlamaAppleRuntime",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "LlamaApple",
            targets: ["LlamaApple"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "LlamaApple",
            url: llamaAppleURL,
            checksum: llamaAppleChecksum
        )
    ]
)
