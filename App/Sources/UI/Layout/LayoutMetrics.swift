import CoreFoundation

/// Shared app layout values, independent of device dimensions and theme colors.
nonisolated enum LayoutMetrics {
    /// Horizontal content margin before a readable-width inset is calculated.
    static let contentMargin: CGFloat = 16

    /// Minimum action-label height; the button style supplies additional padding.
    static let actionLabelMinimumHeight: CGFloat = 44

    /// Space above and below a pinned action inside its safe-area bar.
    static let actionBarVerticalPadding: CGFloat = 8
}
