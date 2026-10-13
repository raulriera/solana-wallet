import SwiftUI
import Themes

/// Owns Files import and default-template export presentation.
struct ThemePacksSection: View {
    @Environment(\.palette) private var palette
    @Bindable var settings: AppearanceSettings
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        Section("Theme Packs") {
            Button("Import Theme…", systemImage: "square.and.arrow.down") {
                guard settings.canStartOperation else { return }
                isImporting = true
            }
                .foregroundStyle(palette.accent)
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.themePack], onCompletion: completeImport)
                .confirmationDialog("Replace Theme?", item: $settings.replacement) { replacement in
                    Button("Replace", role: .destructive) { settings.replace(replacement) }
                } message: { replacement in
                    Text("Replace \(replacement.existing.name) with \(replacement.pack.name)? Windows using this theme will update.")
                }
            Button("Export Default Template…", systemImage: "square.and.arrow.up") { settings.prepareExport() }
                .foregroundStyle(palette.accent)
                .onChange(of: settings.export != nil, initial: true) { _, isReady in isExporting = isReady }
                .fileExporter(isPresented: $isExporting, item: settings.export, defaultFilename: "Theme.xtheme",
                              onCompletion: completeExport, onCancellation: settings.finishExport)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }

    /// Passes the picked file or a picker error to the package workflow.
    /// - Parameter result: The system import dialog's outcome.
    private func completeImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url): settings.importPack(from: url)
        case .failure(let error): settings.report(error, defaultingTo: .importFailed)
        }
    }

    /// Reports export errors before releasing the completed export's staging directory.
    /// - Parameter result: The system export dialog's outcome.
    private func completeExport(_ result: Result<URL, any Error>) {
        if case .failure(let error) = result { settings.report(error, defaultingTo: .exportFailed) }
        settings.finishExport()
    }
}
