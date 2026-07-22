import AppKit

/// The menu-bar glyph: a rounded-rect archive box with a lid seam near the top
/// (the `.g`/`.bd` pattern in the mock, 14×11 @1.5px stroke). Rendered as a *template*
/// NSImage so macOS tints it automatically — black in a light menu bar, white in dark.
/// The badge (blue/amber/red) is drawn separately in SwiftUI and keeps its color.
enum MenuGlyph {

    /// Cached default glyph for the menu bar.
    static let shared: NSImage = make()

    static func make(size: CGSize = CGSize(width: 17, height: 13)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let line: CGFloat = 1.5
            let inset = line / 2

            // Leave a little room on the right/top so the badge can overhang the corner
            // without the glyph feeling cramped against it.
            let boxRect = NSRect(
                x: rect.minX + inset,
                y: rect.minY + inset,
                width: rect.width - line - 2,
                height: rect.height - line - 1
            )

            NSColor.black.setStroke()

            let box = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)
            box.lineWidth = line
            box.stroke()

            // Lid seam ~2pt below the top edge.
            let lidY = boxRect.maxY - 3
            let lid = NSBezierPath()
            lid.move(to: CGPoint(x: boxRect.minX + 2.5, y: lidY))
            lid.line(to: CGPoint(x: boxRect.maxX - 2.5, y: lidY))
            lid.lineWidth = line
            lid.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
