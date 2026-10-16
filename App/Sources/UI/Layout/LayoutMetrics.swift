import CoreFoundation

/// Shared app layout values, independent of device dimensions and theme colors.
nonisolated enum LayoutMetrics {
    /// The widest that content grows, matching Settings on iPad.
    static let readableWidth: CGFloat = 896
}
