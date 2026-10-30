import Foundation
import Themes

/// The theme catalog, appearance preferences, and theme pack services.
struct AppearanceServices {
    let catalog: any ThemeCatalogProviding
    let appearance: any AppearanceCoordinating
    let packages: any PackServicing

    /// Creates the production appearance services.
    init() {
        guard let url = OriginalAppearance.packageURL else { preconditionFailure("The app bundle is missing the original theme.") }
        let builtIns = [BundledTheme(id: OriginalAppearance.id, name: "Original", url: url)]
        let directory = URL.persistentDirectory.appending(path: "Themes", directoryHint: .isDirectory)
        packages = PackService()
        catalog = ThemeCatalog(directory: directory, builtIns: builtIns, packages: packages)
        appearance = AppearanceCoordinator(
            store: AppearanceStore(directory: directory, builtIns: builtIns),
            recovery: SettingsRecoveryRequest()
        )
    }
}
