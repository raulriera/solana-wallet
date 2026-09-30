import SwiftUI

/// Owns navigation, presentations, and rendered appearance independently for one window.
struct AppearanceScene: View {
    private enum Destination: Hashable { case appearance }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var settings: AppearanceSettings
    @State private var rendered = RenderedAppearance()
    @State private var selection: Destination? = .appearance
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    private let services: AppearanceServices
    let wallet: AppearanceWallet?

    /// Creates scene-owned UI state using application-owned services.
    /// - Parameters:
    ///   - services: Shared catalog, package operations, and preference snapshots.
    ///   - wallet: The owning window's selected wallet, if one exists.
    init(services: AppearanceServices, wallet: AppearanceWallet? = nil) {
        self.services = services
        self.wallet = wallet
        _settings = State(initialValue: AppearanceSettings(
            appearance: services.appearance, catalog: services.catalog, packages: services.packages
        ))
    }

    private var palette: RenderedPalette { rendered.palette(scheme: colorScheme, contrast: contrast) }
    private var selectedTheme: ThemeEntry? { services.appearance.snapshot?.theme(for: wallet?.id) }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            List(selection: $selection) {
                NavigationLink("Appearance", value: Destination.appearance)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            NavigationStack {
                AppearanceView(settings: settings, wallet: wallet, palette: palette)
            }
        }
        .tint(palette.accent)
        .task(id: scenePhase) {
            if scenePhase == .active { await settings.activate() }
        }
        .task(id: selectedTheme?.revision) {
            do { try await rendered.load(selectedTheme, catalog: services.catalog, packages: services.packages) }
            catch { settings.report(error) }
        }
        .alert("Appearance Unavailable", isPresented: Binding(
            get: { settings.failure != nil }, set: { if !$0 { settings.failure = nil } }
        )) {
            Button("OK") { settings.failure = nil }
        } message: { Text(settings.failure ?? "") }
        .onDisappear { settings.cancel() }
    }
}
