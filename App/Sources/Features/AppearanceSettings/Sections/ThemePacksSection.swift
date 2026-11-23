import SwiftUI
import Themes

/// A section that imports theme packs and exports the default template.
struct ThemePacksSection: View {
    @Bindable var settings: AppearanceSettingsModel
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        Section("Theme Packs") {
            Button("Import Theme…", systemImage: "square.and.arrow.down") {
                guard settings.canStartOperation else { return }
                isImporting = true
            }
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.themePack], onCompletion: completeImport)
                .confirmation("Replace Theme?", action: "Replace", item: $settings.replacement,
                              perform: settings.replace) { replacement in
                    Text("Replace \(replacement.existing.name) with \(replacement.pack.name)? Windows using this theme will update.")
                }
            Button("Export Default Template…", systemImage: "square.and.arrow.up") { settings.prepareExport() }
                .onChange(of: settings.export != nil, initial: true) { _, isReady in isExporting = isReady }
                .fileExporter(isPresented: $isExporting, item: settings.export, defaultFilename: "Theme.xtheme",
                              onCompletion: completeExport, onCancellation: settings.finishExport)
        }
    }

    /// Imports the picked file or reports the picker's error.
    ///
    /// - Parameter result: The file importer's result.
    private func completeImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url): settings.importPack(from: url)
        case .failure(let error): settings.report(error, defaultingTo: .importFailed)
        }
    }

    /// Reports an export error and finishes the export.
    ///
    /// - Parameter result: The file exporter's result.
    private func completeExport(_ result: Result<URL, any Error>) {
        if case .failure(let error) = result { settings.report(error, defaultingTo: .exportFailed) }
        settings.finishExport()
    }
}
