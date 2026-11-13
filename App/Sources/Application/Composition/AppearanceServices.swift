import Foundation
import Themes

/// The theme catalog, appearance preferences, and theme pack services.
struct AppearanceServices {
    let catalog: any ThemeCatalogProviding
    let appearance: any AppearanceCoordinating
    let packages: any PackServicing

    /// Creates the production appearance services.
    init() {
        guard let original = BundledTheme.original, let solana = BundledTheme.solana else {
            preconditionFailure("The app bundle is missing a built-in theme.")
        }
        let builtIns = [original, solana]
        let directory = URL.persistentDirectory.appending(path: "Themes", directoryHint: .isDirectory)
        packages = PackService()
        catalog = ThemeCatalog(directory: directory, builtIns: builtIns, packages: packages)
        appearance = AppearanceCoordinator(
            store: AppearanceStore(directory: directory, builtIns: builtIns),
            recovery: SettingsRecoveryRequest()
        )
    }
}
