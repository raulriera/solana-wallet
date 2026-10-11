import SwiftUI

/// The system split view for a section inside the window's tab view, reaching the window's top edge.
///
/// On iPad, a tab view that appears after the window's first frame lays split view columns out below
/// its top tab bar, which leaves a white band above them. The columns draw their own navigation bars,
/// so they can extend under the tab bar the way they do when the tab view is present from the start.
struct TabSectionNavigationSplitViewStyle: NavigationSplitViewStyle {
    /// Extends the system split view through the top safe area.
    /// - Parameter configuration: The split view's columns.
    /// - Returns: The system split view, reaching the window's top edge.
    func makeBody(configuration: Configuration) -> some View {
        AutomaticNavigationSplitViewStyle().makeBody(configuration: configuration)
            .ignoresSafeArea(edges: .top)
    }
}

extension NavigationSplitViewStyle where Self == TabSectionNavigationSplitViewStyle {
    /// A system split view for a tab's section that reaches the window's top edge behind the tab bar.
    static var tabSection: Self { Self() }
}
