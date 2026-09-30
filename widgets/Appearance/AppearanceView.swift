import SwiftUI
import Themes

/// Stable identity and display name supplied by the owning wallet window.
struct AppearanceWallet {
    let id: UUID
    let name: String
}

/// Native appearance controls with no package decoding or persistence in its body.
struct AppearanceView: View {
    @Bindable var settings: AppearanceSettings
    let wallet: AppearanceWallet?
    let palette: RenderedPalette
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ThemeChooser(settings: settings, scope: .application, palette: palette)
                } label: {
                    LabeledContent("App Theme", value: appThemeName)
                }
                if let wallet {
                    NavigationLink {
                        ThemeChooser(settings: settings, scope: .wallet(wallet.id), palette: palette)
                    } label: {
                        LabeledContent("Wallet Theme", value: walletThemeName(wallet))
                    }
                }
            } footer: {
                if let wallet { Text("Wallet Theme applies to \(wallet.name) in every window.") }
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)

            Section("Theme Packs") {
                Button("Import Theme…", systemImage: "square.and.arrow.down") { isImporting = true }
                    .foregroundStyle(palette.accent)
                    .confirmationDialog("Replace Theme?", item: $settings.replacement) { replacement in
                        Button("Replace", role: .destructive) { settings.replace(replacement) }
                    } message: { replacement in
                        Text("Replace \(replacement.existing.name) with \(replacement.pack.name)? Windows using this theme will update.")
                    }
                Button("Export Default Template…", systemImage: "square.and.arrow.up") { settings.prepareExport() }
                    .foregroundStyle(palette.accent)
                ForEach(settings.entries.filter { $0.origin == .custom }) { entry in
                    ThemePackRow(entry: entry, palette: palette) {
                        settings.prepareExport(entry)
                    } remove: { approved in
                        settings.remove(approved)
                    }
                }
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)

            if let activity = settings.activity {
                Section {
                    HStack { ProgressView(); Text(activity).foregroundStyle(palette.secondaryText) }
                }
                .listRowBackground(palette.surface)
            }
        }
        .navigationTitle("Appearance")
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(settings.activity != nil || settings.appearance.snapshot == nil)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.themePack]) { result in
            switch result {
            case .success(let url): settings.importPack(from: url)
            case .failure(let error): settings.report(error)
            }
        }
        .onChange(of: settings.export?.url) { _, url in isExporting = url != nil }
        .fileExporter(isPresented: $isExporting, item: settings.export, defaultFilename: "Theme.xtheme") { result in
            if case .failure(let error) = result { settings.report(error) }
            settings.finishExport()
        } onCancellation: { settings.finishExport() }
    }

    private var appThemeName: String {
        let snapshot = settings.appearance.snapshot
        return snapshot?.preferences.appThemeID.flatMap { snapshot?.entries[$0]?.name } ?? "Original"
    }

    /// Looks up an explicit wallet override without substituting the inherited theme's name.
    /// - Parameter wallet: The current window's wallet.
    /// - Returns: The override name or the explicit inheritance label.
    private func walletThemeName(_ wallet: AppearanceWallet) -> String {
        let snapshot = settings.appearance.snapshot
        return snapshot?.preferences.walletThemeIDs[wallet.id].flatMap { snapshot?.entries[$0]?.name } ?? "Use App Default"
    }
}
