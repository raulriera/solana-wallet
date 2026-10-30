import Foundation
import Observation
import Themes

/// A window's workflow for selecting, importing, exporting, and removing themes.
@MainActor @Observable final class AppearanceSettingsModel: ThemeActions {
    /// An asynchronous action on the main actor.
    private typealias Action = @MainActor () async throws -> Void

    /// An imported package and the installed theme it replaces.
    struct Replacement: Identifiable, Equatable {
        let pack: Pack
        let existing: ThemeEntry
        var id: UUID { existing.revision }
    }

    let appearance: any AppearanceCoordinating
    private let catalog: any ThemeCatalogProviding
    private let packages: any PackServicing
    private(set) var export: ThemeExport?
    var replacement: Replacement?
    var error: ThemeError?
    @ObservationIgnored private var operation: Task<Void, Never>?

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - appearance: The shared theme selections.
    ///   - catalog: The theme catalog.
    ///   - packages: The service that reads and writes packages.
    init(appearance: any AppearanceCoordinating, catalog: any ThemeCatalogProviding,
         packages: any PackServicing) {
        self.appearance = appearance
        self.catalog = catalog
        self.packages = packages
    }

    var entries: [ThemeEntry] { appearance.snapshot?.orderedEntries ?? [] }
    var entryIDs: [UUID] { appearance.snapshot?.orderedEntryIDs ?? [] }

    var canStartOperation: Bool { operation == nil && export == nil && replacement == nil }

    func select(_ id: UUID?, for scope: AppearancePreferences.Scope) {
        run(defaultingTo: .saveFailed) { try await self.appearance.select(id, for: scope) }
    }

    /// Imports a theme package without selecting it.
    ///
    /// - Parameter url: The package's security-scoped URL.
    func importPack(from url: URL) {
        run(defaultingTo: .saveFailed) {
            let pack: Pack
            do { pack = try await self.packages.read(from: url) }
            catch let error where !(error is CancellationError) { throw ThemeError.importFailed }
            do {
                _ = try await self.catalog.install(pack)
                try await self.reloadAfterCommit()
            } catch ThemeCatalogError.replacementRequired(let existing) {
                self.replacement = Replacement(pack: pack, existing: existing)
            }
        }
    }

    /// Replaces an installed theme with an imported package.
    ///
    /// - Parameter approved: The approved replacement.
    func replace(_ approved: Replacement) {
        replacement = nil
        run(defaultingTo: .saveFailed) {
            _ = try await self.catalog.install(approved.pack, replacing: approved.existing)
            try await self.reloadAfterCommit()
        }
    }

    func remove(_ entry: ThemeEntry) {
        run(defaultingTo: .saveFailed) {
            try await self.catalog.remove(entry)
            try await self.reloadAfterCommit()
        }
    }

    /// Writes the default theme template to a temporary file for export.
    func prepareExport() {
        run(defaultingTo: .exportFailed) {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = root.appendingPathComponent("Theme.xtheme")
            do {
                try await CatalogIO.perform { _ in
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                }
                try await self.packages.exportTemplate(named: "My Theme", defaults: OriginalAppearance.colors, to: url)
                try Task.checkCancellation()
                self.export = ThemeExport(url: url)
            } catch {
                await CatalogIO.discard(root)
                throw error
            }
        }
    }

    /// Deletes the exported template's temporary file.
    func finishExport() {
        guard let export else { return }
        self.export = nil
        Task { @concurrent in await CatalogIO.discard(export.url.deletingLastPathComponent()) }
    }

    /// Cancels this window's running action, replacement, and export.
    func cancel() {
        operation?.cancel()
        replacement = nil
        finishExport()
    }

    /// Waits for the running action to finish.
    func waitForOperation() async { await operation?.value }

    /// Reloads the shared theme selections without inheriting the caller's cancellation.
    ///
    /// - Throws: A storage error.
    private func reloadAfterCommit() async throws {
        try await Task { try await appearance.reload() }.value
    }

    /// Shows an error unless it's a cancellation.
    ///
    /// - Parameters:
    ///   - error: The error that occurred.
    ///   - fallback: The error to show when the failure has no more specific cause.
    func report(_ error: any Error, defaultingTo fallback: ThemeError) {
        let cocoaError = error as NSError
        guard !Task.isCancelled, !(error is CancellationError),
              !(cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) else { return }
        self.error = switch error {
        case let error as ThemeError: error
        case ThemeCatalogError.builtInTheme: .builtInTheme
        case ThemeCatalogError.changed: .changedElsewhere
        default: fallback
        }
    }

    /// Runs an action unless another is running, and shows its error.
    ///
    /// - Parameters:
    ///   - fallback: The error to show when the action fails without a more specific cause.
    ///   - action: The action to run.
    private func run(defaultingTo fallback: ThemeError, action: @escaping Action) {
        guard canStartOperation else { return }
        operation = Task {
            defer { self.operation = nil }
            do { try await action() }
            catch { self.report(error, defaultingTo: fallback) }
        }
    }
}
