import Foundation
import Themes

/// Shared catalog and preferences, with matching built-ins for every window.
struct AppearanceServices {
    let catalog: any ThemeCatalogProviding
    let appearance: any AppearanceCoordinating
    let packages: any PackServicing

    /// Configures production services without opening installed packages.
    /// - Throws: An invalid bundled resource or catalog configuration error.
    init() throws {
        guard let url = Bundle.main.url(forResource: "Original", withExtension: "xtheme") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let builtIns = [BundledTheme(id: OriginalAppearance.id, name: "Original", url: url)]
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Themes")
        packages = PackService()
        catalog = try ThemeCatalog(directory: directory, builtIns: builtIns, packages: packages)
        appearance = AppearanceCoordinator(
            store: try AppearanceStore(directory: directory, builtIns: builtIns),
            recovery: SettingsRecoveryRequest()
        )
    }
}
