// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "mpv_libs",
  platforms: [.iOS("14.0")],
  products: [
    .library(name: "mpv-libs", targets: ["mpv_libs", "Mpv"]),
  ],
  targets: [
    .binaryTarget(name: "Mpv", path: "Frameworks/Mpv.xcframework"),
    .target(name: "mpv_libs", dependencies: ["Mpv"]),
  ]
)
