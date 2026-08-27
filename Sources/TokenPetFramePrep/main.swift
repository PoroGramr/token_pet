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

for index in 1...5 {
    let input = inputDirectory.appendingPathComponent("\(index).png")
    let output = outputDirectory.appendingPathComponent("\(index).png")
    let sourceData = try Data(contentsOf: input)
    let normalizedData = try FrameImageProcessor.makeNormalizedPNG(from: sourceData, pixelSize: 240)
    try normalizedData.write(to: output, options: .atomic)
}
