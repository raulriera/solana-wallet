import SwiftUI

/// Runs the window's confirmed token removals and explains a failed save.
///
/// It attaches to the portfolio, which stays on screen when a removed token's details close.
private struct TokenRemovalLifecycle: ViewModifier {
    @Bindable var removal: TokenRemovalModel

    /// Runs each confirmed removal and presents a failed save.
    /// - Parameter content: The portfolio scene.
    /// - Returns: The scene with managed removals and error presentation.
    func body(content: Content) -> some View {
        let attempt = removal.attempt
        content
            .task(id: attempt) { await removal.run(attempt) }
            .errorAlert($removal.error)
    }
}

extension PortfolioScene {
    /// Runs the window's token removals while the portfolio is on screen.
    /// - Returns: The scene with managed removals and error presentation.
    func tokenRemovalLifecycle() -> some View {
        modifier(TokenRemovalLifecycle(removal: removal))
    }
}
