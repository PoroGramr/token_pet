import Foundation
import TokenPetCore

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: TokenPetFramePrep <input-directory> <output-directory>\n".utf8))
    exit(64)
}

let inputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let enumerator = FileManager.default.enumerator(
    at: inputDirectory,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
)
let inputPaths = (enumerator?.allObjects as? [URL] ?? [])
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.path < $1.path }

guard !inputPaths.isEmpty else {
    throw CocoaError(.fileNoSuchFile)
}

for input in inputPaths {
    let relativePath = input.path.replacingOccurrences(of: inputDirectory.path + "/", with: "")
    let output = outputDirectory.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let normalizedData = try FrameImageProcessor.makeNormalizedPNG(from: Data(contentsOf: input), pixelSize: 240)
    try normalizedData.write(to: output, options: .atomic)
}
