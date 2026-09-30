import Foundation
import Observation
import Themes

/// One window's package workflow; committed selections are shared through the coordinator.
@MainActor @Observable final class AppearanceSettings {
    /// Exact snapshot and installed revision awaiting replacement approval.
    struct Replacement: Identifiable {
        let pack: Pack
        let existing: ThemeEntry
        var id: UUID { existing.revision }
    }

    let appearance: any AppearanceCoordinating
    private let catalog: any ThemeCatalogProviding
    private let packages: any PackServicing
    private(set) var activity: String?
    private(set) var export: ThemeExport?
    var replacement: Replacement?
    var failure: String?
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
    var customEntries: [ThemeEntry] { appearance.snapshot?.customEntries ?? [] }

    /// Loads current metadata and applies external Settings recovery.
    func activate() async {
        do { try await appearance.activate() }
        catch { report(error) }
    }

    /// Saves before publishing a checkmark or changing any window's appearance.
    /// - Parameters:
    ///   - id: A selected theme, or `nil` for inheritance.
    ///   - scope: The application or selected wallet.
    func select(_ id: UUID?, for scope: AppearancePreferences.Scope) {
        run("Saving Appearance…") { try await self.appearance.select(id, for: scope) }
    }

    /// Reads an independent package snapshot and installs without selecting it.
    /// - Parameter url: The security-scoped URL returned by the Files picker.
    func importPack(from url: URL) {
        run("Importing Theme…") {
            let pack = try await self.packages.read(from: url)
            do {
                _ = try await self.catalog.install(pack)
                try await self.reloadAfterCommit()
            } catch ThemeCatalog.Failure.replacementRequired(let existing) {
                self.replacement = Replacement(pack: pack, existing: existing)
            }
        }
    }

    /// Replaces only the installed revision the user explicitly approved.
    /// - Parameter approved: The retained import snapshot and exact installed revision.
    func replace(_ approved: Replacement) {
        replacement = nil
        run("Replacing Theme…") {
            _ = try await self.catalog.install(approved.pack, replacing: approved.existing)
            try await self.reloadAfterCommit()
        }
    }

    /// Removes an approved custom revision and reloads its atomic preference fallbacks.
    /// - Parameter entry: The exact entry presented in the removal confirmation.
    func remove(_ entry: ThemeEntry) {
        run("Removing Theme…") {
            try await self.catalog.remove(entry)
            try await self.reloadAfterCommit()
        }
    }

    /// Prepares a complete package before presenting the system destination picker.
    /// - Parameter entry: A custom theme to export, or `nil` for a new default template.
    func prepareExport(_ entry: ThemeEntry? = nil) {
        run("Preparing Export…") {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = root.appendingPathComponent("Theme.xtheme")
            do {
                try await CatalogIO.perform { _ in
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                }
                if let entry {
                    let pack = try await self.catalog.pack(for: entry)
                    try await self.packages.export(pack, defaults: OriginalAppearance.colors, to: url)
                } else {
                    try await self.packages.exportTemplate(named: "My Theme", defaults: OriginalAppearance.colors, to: url)
                }
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

    /// Converts actionable failures to presentation text; cancellation is silent.
    /// - Parameter error: An error from a service or a system file dialog.
    func report(_ error: any Error) {
        let cocoaError = error as NSError
        guard !Task.isCancelled, !(error is CancellationError),
              !(cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) else { return }
        switch error {
        case ThemeCatalog.Failure.builtInTheme: failure = "Built-in themes cannot be replaced or removed."
        case ThemeCatalog.Failure.changed: failure = "This theme changed in another window. Try again."
        default: failure = error.localizedDescription
        }
    }

    /// Serializes this window's user actions while service work suspends the main actor.
    /// - Parameters:
    ///   - activity: A short progress description.
    ///   - action: Service calls and small presentation-state updates.
    private func run(_ activity: String, action: @escaping @MainActor () async throws -> Void) {
        guard operation == nil, export == nil, replacement == nil else { return }
        self.activity = activity
        operation = Task {
            defer { self.activity = nil; self.operation = nil }
            do { try await action() }
            catch { self.report(error) }
        }
    }
}
