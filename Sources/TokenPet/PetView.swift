import AppKit
import TokenPetCore

@MainActor
final class PetView: NSView {
    private var frames: [NSImage] = []
    private var playbackIndices: [Int] = []
    private var percentPosition = NormalizedPoint(x: 0.5, y: 52.0 / 120.0)
    private var percentFontSize: Double = 22
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var presentation = WidgetPresentation(state: .loading)
    var contextMenu: NSMenu?

    override init(frame frameRect: NSRect) {
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

    func apply(character: RuntimeCharacter) {
        let frameCountChanged = frames.count != character.frames.count
        frames = character.frames
        playbackIndices = character.playbackIndices.filter { frames.indices.contains($0) }
        percentPosition = character.profile.percentPosition
        percentFontSize = character.profile.percentFontSize
        frameIndex = 0
        if frameCountChanged {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        if window != nil {
            startAnimation()
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .none

        if let imageIndex = playbackIndices.indices.isEmpty ? nil : playbackIndices[frameIndex % playbackIndices.count] {
            let image = frames[imageIndex]
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

        PercentTextDrawing.draw(
            text: presentation.text,
            in: bounds,
            position: percentPosition,
            fontSize: percentFontSize
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
        guard playbackIndices.count > 1, animationTimer == nil else { return }
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
        guard !playbackIndices.isEmpty else { return }
        frameIndex = (frameIndex + 1) % playbackIndices.count
        needsDisplay = true
    }
}
