// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TokenPet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenPetCore", targets: ["TokenPetCore"]),
        .executable(name: "TokenPet", targets: ["TokenPet"]),
        .executable(name: "TokenPetFramePrep", targets: ["TokenPetFramePrep"]),
        .executable(name: "TokenPetServiceTests", targets: ["TokenPetServiceTests"]),
        .executable(name: "TokenPetCoreTests", targets: ["TokenPetCoreTests"]),
        .executable(name: "TokenPetCharacterStoreTests", targets: ["TokenPetCharacterStoreTests"])
    ],
    targets: [
        .target(name: "TokenPetCore"),
        .executableTarget(name: "TokenPet", dependencies: ["TokenPetCore"]),
        .executableTarget(name: "TokenPetFramePrep", dependencies: ["TokenPetCore"]),
        .executableTarget(
            name: "TokenPetServiceTests",
            dependencies: ["TokenPetCore"],
            path: "Tests/TokenPetServiceTests"
        ),
        .executableTarget(
            name: "TokenPetCoreTests",
            dependencies: ["TokenPetCore"],
            path: "Tests/TokenPetCoreTests"
        ),
        .executableTarget(
            name: "TokenPetCharacterStoreTests",
            dependencies: ["TokenPetCore"],
            path: "Tests/TokenPetCharacterStoreTests"
        )
    ]
)
