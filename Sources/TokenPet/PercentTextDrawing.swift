import AppKit
import TokenPetCore

enum PercentTextDrawing {
    static func attributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor(calibratedRed: 0.01, green: 0.08, blue: 0.22, alpha: 1),
            .strokeWidth: -3,
            .paragraphStyle: paragraph
        ]
    }

    static func draw(
        text: String,
        in bounds: NSRect,
        position: NormalizedPoint,
        fontSize: CGFloat
    ) {
        let attributes = attributes(fontSize: fontSize)
        let measuredTextSize = (text as NSString).size(withAttributes: attributes)
        let textRect = PercentLayout.textRect(
            containerSize: bounds.size,
            position: position,
            fontSize: fontSize,
            measuredTextSize: measuredTextSize
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
}
