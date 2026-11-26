import SwiftUI

/// A layout that places the payment keypad's keys in rows of three, with gaps and margins that scale with the keys.
struct KeypadLayout: Layout {
    private static let columns = 3
    /// The side of a key at the largest size.
    private static let largestKey: CGFloat = 70
    private static let largestColumnGap: CGFloat = 30
    /// The gap between rows and the margin above and below the keys, at the largest size.
    private static let largestRowGap: CGFloat = 18

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.size(fitting: proposal, count: subviews.count)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let frame = Self.frame(ofKeyAt: index, count: subviews.count, in: bounds)
            subview.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }

    /// Returns the keypad's largest size, scaled down to fit a proposal.
    ///
    /// - Parameters:
    ///   - proposal: The space offered to the keypad; an unspecified dimension doesn't limit it.
    ///   - count: The number of keys.
    /// - Returns: The keypad's size, with its keys, gaps, and margins.
    static func size(fitting proposal: ProposedViewSize, count: Int) -> CGSize {
        let largest = largestSize(count: count)
        let scale = scale(fitting: proposal, count: count)
        return CGSize(width: largest.width * scale, height: largest.height * scale)
    }

    /// Returns a key's frame, with the keypad centered in its bounds.
    ///
    /// - Parameters:
    ///   - index: The key's position, row by row from the top leading key.
    ///   - count: The number of keys.
    ///   - bounds: The keypad's frame.
    /// - Returns: The key's square frame.
    static func frame(ofKeyAt index: Int, count: Int, in bounds: CGRect) -> CGRect {
        let proposal = ProposedViewSize(bounds.size)
        let scale = scale(fitting: proposal, count: count)
        let size = size(fitting: proposal, count: count)
        let key = largestKey * scale
        let column = CGFloat(index % columns)
        let row = CGFloat(index / columns)
        return CGRect(x: bounds.midX - size.width / 2 + column * (key + largestColumnGap * scale),
                      y: bounds.midY - size.height / 2 + largestRowGap * scale + row * (key + largestRowGap * scale),
                      width: key, height: key)
    }

    /// Returns the gap between rows in a keypad of a size.
    ///
    /// - Parameters:
    ///   - size: The keypad's size.
    ///   - count: The number of keys.
    /// - Returns: The gap between rows.
    static func rowGap(inKeypadOf size: CGSize, count: Int) -> CGFloat {
        largestRowGap * scale(fitting: ProposedViewSize(size), count: count)
    }

    /// Returns how much the keypad shrinks from its largest size to fit a proposal.
    ///
    /// - Parameters:
    ///   - proposal: The space offered to the keypad; an unspecified dimension doesn't limit it.
    ///   - count: The number of keys.
    /// - Returns: A scale from zero to one; one where the largest keypad fits.
    private static func scale(fitting proposal: ProposedViewSize, count: Int) -> CGFloat {
        let largest = largestSize(count: count)
        guard largest.height > 0 else { return 0 }
        return min(1, (proposal.width ?? .infinity) / largest.width, (proposal.height ?? .infinity) / largest.height)
    }

    /// Returns the keypad's size with its largest keys, gaps, and margins.
    ///
    /// - Parameter count: The number of keys.
    /// - Returns: The largest keypad's size, or zero without keys.
    private static func largestSize(count: Int) -> CGSize {
        let rows = CGFloat((count + columns - 1) / columns)
        guard rows > 0 else { return .zero }
        let columns = CGFloat(columns)
        return CGSize(width: columns * largestKey + (columns - 1) * largestColumnGap,
                      height: rows * largestKey + (rows + 1) * largestRowGap)
    }
}
