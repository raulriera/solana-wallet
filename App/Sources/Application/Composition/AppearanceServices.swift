import Foundation
import Themes

/// Shared catalog and preferences, with matching built-ins for every window.
struct AppearanceServices {
    let catalog: any ThemeCatalogProviding
    let appearance: any AppearanceCoordinating
    let packages: any PackServicing

    /// Configures production services without opening installed packages.
    init() {
        guard let url = OriginalAppearance.packageURL else { preconditionFailure("The app bundle is missing the original theme.") }
        let builtIns = [BundledTheme(id: OriginalAppearance.id, name: "Original", url: url)]
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Themes")
        packages = PackService()
        catalog = ThemeCatalog(directory: directory, builtIns: builtIns, packages: packages)
        appearance = AppearanceCoordinator(
            store: AppearanceStore(directory: directory, builtIns: builtIns),
            recovery: SettingsRecoveryRequest()
        )
    }
}
