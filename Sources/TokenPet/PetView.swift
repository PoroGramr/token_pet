import AppKit
import TokenPetCore

@MainActor
final class PetView: NSView {
    private let frames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var presentation = WidgetPresentation(state: .loading)
    var contextMenu: NSMenu?

    override init(frame frameRect: NSRect) {
        frames = Self.loadFrames()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            startAnimation()
        }
    }

    func update(state: UsageDisplayState) {
        presentation = WidgetPresentation(state: state)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .none

        if !frames.isEmpty {
            let image = frames[frameIndex % frames.count]
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let destination = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor(calibratedRed: 0.01, green: 0.08, blue: 0.22, alpha: 1),
            .strokeWidth: -3,
            .paragraphStyle: paragraph
        ]
        presentation.text.draw(
            in: NSRect(x: 0, y: 37, width: bounds.width, height: 30),
            withAttributes: attributes
        )

        if presentation.showsWarning {
            let warningAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .black),
                .foregroundColor: NSColor.systemRed
            ]
            "!".draw(at: NSPoint(x: 96, y: 75), withAttributes: warningAttributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    private func startAnimation() {
        guard frames.count > 1, animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1 / Double(FrameSequence.framesPerSecond),
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func advanceFrame() {
        frameIndex = (frameIndex + 1) % frames.count
        needsDisplay = true
    }

    private static func loadFrames() -> [NSImage] {
        let uniqueFrames = Dictionary(uniqueKeysWithValues: (1...5).compactMap { index -> (Int, NSImage)? in
            guard let url = frameURL(index: index), let data = try? Data(contentsOf: url),
                  let cgImage = try? FrameImageProcessor.makeTransparentImage(from: data) else {
                return nil
            }
            return (index, NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        })
        return FrameSequence.indices.compactMap { uniqueFrames[$0] }
    }

    private static func frameURL(index: Int) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Frames/\(index).png")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("img/\(index).png")
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }
}
