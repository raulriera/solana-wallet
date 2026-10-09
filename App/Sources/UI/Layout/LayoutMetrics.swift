import CoreFoundation

/// Shared app layout values, independent of device dimensions and theme colors.
nonisolated enum LayoutMetrics {
    /// Horizontal content margin before a readable-width inset is calculated.
    static let contentMargin: CGFloat = 16

    /// Space above and below a pinned action inside its safe-area bar.
    static let actionBarVerticalPadding: CGFloat = 8
}
