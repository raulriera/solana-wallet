import SwiftUI

/// Lays out an adaptive arrangement's regions around the active fold that crosses it.
struct AdaptiveArrangement: View {
    /// The active fold that crosses the arrangement, in the arrangement's own coordinates.
    @State private var fold: CGRect?
    let configuration: ArrangementViewStyleConfiguration

    var body: some View {
        // The secondary region's views lay out one by one, so its second view can move under the primary region.
        Group(subviews: configuration.secondary) { secondary in
            AdaptiveArrangementLayout(fold: fold) {
                configuration.primary
                ForEach(secondary) { $0 }
            }
        }
        .onGeometryChange(for: CGRect?.self) { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            return geometry.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
                .first { $0.intersects(bounds) }
        } action: { fold in
            self.fold = fold
        }
    }
}
