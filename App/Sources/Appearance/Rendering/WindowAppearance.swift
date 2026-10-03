import SwiftUI

/// Owns rendered colors and appearance loading for one window's view hierarchy.
private struct WindowAppearance: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var rendered = RenderedAppearance()
    @State private var failure: String?
    let services: AppearanceServices
    let walletID: UUID?

    private var palette: RenderedPalette { rendered.palette(scheme: colorScheme, contrast: contrast) }
    private var selectedTheme: ThemeEntry? { services.appearance.snapshot?.theme(for: walletID) }

    /// Installs this window's palette, tint, loading tasks, and error presentation.
    /// - Parameter content: The window's feature hierarchy.
    /// - Returns: Content inheriting the resolved appearance.
    func body(content: Content) -> some View {
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .task(id: scenePhase) {
                if scenePhase == .active {
                    do { try await services.appearance.activate() }
                    catch { report(error) }
                }
            }
            .task(id: selectedTheme?.revision) { await loadSelectedTheme() }
            .alert("Appearance Unavailable", item: $failure) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in Text(failure) }
    }

    /// Refreshes this window's colors without exposing package loading to feature scenes.
    private func loadSelectedTheme() async {
        do { try await rendered.load(selectedTheme, catalog: services.catalog, packages: services.packages) }
        catch { report(error) }
    }

    /// Presents appearance failures only while this window's task is still active.
    /// - Parameter error: A theme loading or preference activation failure.
    private func report(_ error: any Error) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        failure = error.localizedDescription
    }
}

extension View {
    /// Owns appearance once at a window's root and shares its colors with descendants.
    /// - Parameters:
    ///   - services: Shared appearance services, without window-specific rendered state.
    ///   - walletID: The owning window's selected wallet, or `nil` to follow the app default.
    /// - Returns: A view with an independent appearance lifecycle.
    func windowAppearance(services: AppearanceServices, walletID: UUID? = nil) -> some View {
        modifier(WindowAppearance(services: services, walletID: walletID))
    }
}
