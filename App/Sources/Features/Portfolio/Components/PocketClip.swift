import SwiftUI

/// A shape that covers everything above a pocket's lip, which runs along the bottom edge and dips at its center.
nonisolated struct PocketClip: Shape {
    func path(in rect: CGRect) -> Path {
        let depth: CGFloat = 18
        let overhang: CGFloat = 32
        return Path { path in
            path.move(to: CGPoint(x: rect.minX - overhang, y: rect.minY - overhang))
            path.addLine(to: CGPoint(x: rect.maxX + overhang, y: rect.minY - overhang))
            path.addLine(to: CGPoint(x: rect.maxX + overhang, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.width * 0.68, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY + depth),
                          control1: CGPoint(x: rect.width * 0.58, y: rect.maxY),
                          control2: CGPoint(x: rect.width * 0.58, y: rect.maxY + depth))
            path.addCurve(to: CGPoint(x: rect.width * 0.32, y: rect.maxY),
                          control1: CGPoint(x: rect.width * 0.42, y: rect.maxY + depth),
                          control2: CGPoint(x: rect.width * 0.42, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX - overhang, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
