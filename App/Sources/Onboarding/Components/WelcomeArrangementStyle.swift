import SwiftUI

/// Keeps both welcome sections visible while adapting to the container's proportions.
struct WelcomeArrangementStyle: ArrangementViewStyle {
    /// Rearranges the same two regions without replacing their view identities.
    /// - Parameter configuration: The introduction and actions supplied by the arrangement.
    /// - Returns: Side-by-side regions in a wide container, or stacked regions in a tall or square container.
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let layout = geometry.size.width > geometry.size.height
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            layout {
                configuration.primary
                configuration.secondary
            }
        }
    }
}

extension ArrangementViewStyle where Self == WelcomeArrangementStyle {
    /// The adaptive arrangement used by the welcome screen.
    static var welcome: WelcomeArrangementStyle { WelcomeArrangementStyle() }
}
