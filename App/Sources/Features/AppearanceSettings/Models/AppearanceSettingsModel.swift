import Foundation
import Observation
import Themes

/// One window's theme selection, import, export, and removal.
@MainActor @Observable final class AppearanceSettingsModel: ThemeActions {
    /// Runs one window's service calls and presentation updates on the main actor.
    private typealias Action = @MainActor () async throws -> Void

    /// Exact snapshot and installed revision awaiting replacement approval.
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

    /// Injects services shared with the other wallet windows.
    /// - Parameters:
    ///   - appearance: Committed preference snapshots.
    ///   - catalog: Installed package operations.
    ///   - packages: Validated import and export operations.
    init(appearance: any AppearanceCoordinating, catalog: any ThemeCatalogProviding,
         packages: any PackServicing) {
        self.appearance = appearance
        self.catalog = catalog
        self.packages = packages
    }

    var entries: [ThemeEntry] { appearance.snapshot?.orderedEntries ?? [] }
    var entryIDs: [UUID] { appearance.snapshot?.orderedEntryIDs ?? [] }

    /// Whether an action may start, checked at interaction time without changing control appearance.
    var canStartOperation: Bool { operation == nil && export == nil && replacement == nil }

    /// Saves before publishing a checkmark or changing any window's appearance.
    /// - Parameters:
    ///   - id: A selected theme, or `nil` for inheritance.
    ///   - scope: The application or selected wallet.
    func select(_ id: UUID?, for scope: AppearancePreferences.Scope) {
        run(defaultingTo: .saveFailed) { try await self.appearance.select(id, for: scope) }
    }

    /// Reads an independent package snapshot and installs without selecting it.
    /// - Parameter url: The security-scoped URL returned by the Files picker.
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

    /// Replaces only the installed revision the user explicitly approved.
    /// - Parameter approved: The retained import snapshot and exact installed revision.
    func replace(_ approved: Replacement) {
        replacement = nil
        run(defaultingTo: .saveFailed) {
            _ = try await self.catalog.install(approved.pack, replacing: approved.existing)
            try await self.reloadAfterCommit()
        }
    }

    /// Removes an approved custom revision and reloads its atomic preference fallbacks.
    /// - Parameter entry: The exact entry presented in the removal confirmation.
    func remove(_ entry: ThemeEntry) {
        run(defaultingTo: .saveFailed) {
            try await self.catalog.remove(entry)
            try await self.reloadAfterCommit()
        }
    }

    /// Prepares a complete default template before presenting the system destination picker.
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

    /// Releases a staged package only after the system exporter finishes or cancels.
    func finishExport() {
        guard let export else { return }
        self.export = nil
        Task { @concurrent in await CatalogIO.discard(export.url.deletingLastPathComponent()) }
    }

    /// Ends this window's work without stopping operations owned by other windows.
    func cancel() {
        operation?.cancel()
        replacement = nil
        finishExport()
    }

    /// Waits for the current user action, including publication and staging cleanup.
    func waitForOperation() async { await operation?.value }

    /// Publishes a committed catalog mutation even if its initiating window closes.
    /// - Throws: A storage error while refreshing the shared snapshot.
    private func reloadAfterCommit() async throws {
        // Publication belongs to all windows once the catalog has committed.
        try await Task { try await appearance.reload() }.value
    }

    /// Classifies a failure for its alert without keeping the underlying error; cancellation is silent.
    /// - Parameters:
    ///   - error: An error from a service or a system file dialog.
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

    /// Serializes this window's user actions while service work suspends the main actor.
    /// - Parameters:
    ///   - fallback: The error to show when the action fails without a more specific cause.
    ///   - action: Service calls and small presentation-state updates.
    private func run(defaultingTo fallback: ThemeError, action: @escaping Action) {
        guard canStartOperation else { return }
        operation = Task {
            defer { self.operation = nil }
            do { try await action() }
            catch { self.report(error, defaultingTo: fallback) }
        }
    }
}
