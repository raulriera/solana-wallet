import SwiftUI

/// Returns a window to onboarding after the app resets.
///
/// Leaving the wallet ends its tabs' workflows, and onboarding starts with a new draft, so none is left open.
private struct WindowReset: ViewModifier {
    let services: AppServices
    let router: any WindowRouting

    /// Starts onboarding each time any window resets the app.
    /// - Parameter content: The window's root destinations.
    /// - Returns: Content that leaves deleted wallets after a reset.
    func body(content: Content) -> some View {
        content
            .onChange(of: services.resetRevision.value) {
                router.route(to: .onboarding)
            }
    }
}

extension View {
    /// Returns this window to onboarding after any window resets the app.
    /// - Parameters:
    ///   - services: The shared services that count resets.
    ///   - router: The window's navigation.
    /// - Returns: A view whose window starts over after a reset.
    func windowReset(_ services: AppServices, router: any WindowRouting) -> some View {
        modifier(WindowReset(services: services, router: router))
    }
}
