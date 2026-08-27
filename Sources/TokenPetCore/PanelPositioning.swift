import CoreGraphics

public enum PanelPositioning {
    public static func origin(
        saved: CGPoint?,
        panelSize: CGSize,
        visibleScreens: [CGRect],
        margin: CGFloat = 20
    ) -> CGPoint {
        guard let primary = visibleScreens.first else {
            return saved ?? .zero
        }

        if let saved {
            let panelFrame = CGRect(origin: saved, size: panelSize)
            let isVisible = visibleScreens.contains { screen in
                let intersection = screen.intersection(panelFrame)
                return intersection.width >= 24 && intersection.height >= 24
            }
            if isVisible {
                return saved
            }
        }

        return CGPoint(
            x: primary.maxX - panelSize.width - margin,
            y: primary.minY + margin
        )
    }
}
