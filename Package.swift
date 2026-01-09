// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RadioAT",
    products: [
        .library(name: "FMTransmitter", targets: ["FMTransmitter"]),
        .executable(name: "fm-radio", targets: ["fm-radio"]),
    ],
    targets: [
        .target(
            name: "FMTransmitterCLib",
            path: "Sources/FMTransmitterCLib",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++11", "-O3", "-Wall"]),
                .unsafeFlags(["-I/opt/vc/include"]),
                .headerSearchPath("vendor/fm_transmitter"),
                .define("VERSION", to: "\"0.9.6\""),
                .define("EXECUTABLE", to: "\"fm_transmitter\""),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/vc/lib"]),
                .linkedLibrary("m"),
                .linkedLibrary("pthread"),
                .linkedLibrary("bcm_host"),
            ]
        ),
        .target(
            name: "FMTransmitter",
            dependencies: ["FMTransmitterCLib"],
            path: "Sources/FMTransmitter"
        ),
        .executableTarget(
            name: "fm-radio",
            dependencies: ["FMTransmitter"],
            path: "Sources/fm-radio"
        ),
    ]
)
