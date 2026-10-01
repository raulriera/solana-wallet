import SwiftUI

/// Owns settings navigation, presentations, and rendered appearance for one window.
struct SettingsScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appearance: AppearanceSettings
    @State private var rendered = RenderedAppearance()
    @State private var selection: SettingsDestination? = .appearance
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    private let services: AppearanceServices
    let wallet: AppearanceWallet?

    /// Creates scene-owned UI state using application-owned services.
    ///
    /// Services seed this scene's state once and must remain stable for its lifetime.
    /// - Parameters:
    ///   - services: Shared catalog, package operations, and preference snapshots.
    ///   - wallet: The owning window's selected wallet, if one exists.
    init(services: AppearanceServices, wallet: AppearanceWallet? = nil) {
        self.services = services
        self.wallet = wallet
        _appearance = State(initialValue: AppearanceSettings(
            appearance: services.appearance, catalog: services.catalog, packages: services.packages
        ))
    }

    private var palette: RenderedPalette { rendered.palette(scheme: colorScheme, contrast: contrast) }
    private var selectedTheme: ThemeEntry? { services.appearance.snapshot?.theme(for: wallet?.id) }

    var body: some View {
        @Bindable var appearance = appearance

        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            NavigationStack {
                switch selection ?? .appearance {
                case .appearance:
                    AppearanceView(settings: appearance, wallet: wallet, palettes: rendered)
                }
            }
        }
        .tint(palette.accent)
        .task(id: scenePhase) {
            if scenePhase == .active { await appearance.activate() }
        }
        .task(id: selectedTheme?.revision) { await loadSelectedTheme() }
        .alert("Appearance Unavailable", item: $appearance.failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in Text(failure) }
        .onDisappear { appearance.cancel() }
    }

    /// Refreshes cached window colors and reports failures through the native alert.
    private func loadSelectedTheme() async {
        do { try await rendered.load(selectedTheme, catalog: services.catalog, packages: services.packages) }
        catch { appearance.report(error) }
    }
}
