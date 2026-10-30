import SwiftUI

/// A system split view style for a section in a tab view that reaches the window's top edge.
struct TabSectionNavigationSplitViewStyle: NavigationSplitViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        AutomaticNavigationSplitViewStyle().makeBody(configuration: configuration)
            .ignoresSafeArea(edges: .top)
    }
}

extension NavigationSplitViewStyle where Self == TabSectionNavigationSplitViewStyle {
    /// A system split view for a tab's section that reaches the window's top edge.
    static var tabSection: Self { Self() }
}
