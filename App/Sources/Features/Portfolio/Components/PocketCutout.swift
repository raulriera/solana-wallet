import SwiftUI

/// The outline of the pocket at the bottom of the card stack, with a shallow cutout at the top center.
nonisolated struct PocketCutout: Shape {
    /// Draws the pocket in the available space.
    /// - Parameter rect: The pocket's bounds.
    /// - Returns: The closed pocket outline.
    func path(in rect: CGRect) -> Path {
        let depth: CGFloat = 18
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.width * 0.32, y: rect.minY))
            path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY + depth),
                          control1: CGPoint(x: rect.width * 0.42, y: rect.minY),
                          control2: CGPoint(x: rect.width * 0.42, y: rect.minY + depth))
            path.addCurve(to: CGPoint(x: rect.width * 0.68, y: rect.minY),
                          control1: CGPoint(x: rect.width * 0.58, y: rect.minY + depth),
                          control2: CGPoint(x: rect.width * 0.58, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
