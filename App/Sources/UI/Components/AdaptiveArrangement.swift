import SwiftUI

/// Lays out an arrangement's regions around an active fold that crosses it.
struct AdaptiveArrangement: View {
    /// The active fold's frame in the arrangement's coordinates.
    @State private var fold: CGRect?
    let configuration: ArrangementViewStyleConfiguration

    var body: some View {
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
