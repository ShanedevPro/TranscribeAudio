// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscribeAudioMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "TranscribeAudioMac", targets: ["TranscribeAudioMac"]),
    ],
    targets: [
        .executableTarget(
            name: "TranscribeAudioMac",
            path: "Sources/TranscribeAudioMac"
        ),
    ]
)
