// swift-tools-version:5.9
// TitleCaseKit: the rule engine behind Title Capitalizr (style guides, text tools, batch).
// Pure Foundation, shared by the app, the share extension, the widgets and the App Intents.
// `swift test` in this folder runs the per-guide example tests.
import PackageDescription

let package = Package(
    name: "TitleCaseKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TitleCaseKit", targets: ["TitleCaseKit"])],
    targets: [
        .target(name: "TitleCaseKit"),
        .testTarget(name: "TitleCaseKitTests", dependencies: ["TitleCaseKit"]),
    ]
)
