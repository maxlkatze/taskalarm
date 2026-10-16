// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TaskAlarm",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TaskAlarm",
            path: "Sources/TaskAlarm"
        )
    ]
)
