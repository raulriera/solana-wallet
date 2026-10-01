import SwiftUI

/// Hosts one window's feature navigation and owns its resolved appearance.
struct WindowRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var rendered = RenderedAppearance()
    @State private var failure: String?
    let services: AppearanceServices

    private var palette: RenderedPalette { rendered.palette(scheme: colorScheme, contrast: contrast) }
    private var selectedTheme: ThemeEntry? { services.appearance.snapshot?.theme(for: nil) }

    var body: some View {
        OnboardingScene()
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
