import Foundation

/// Theme identities shared across windows, independent of packages and rendered colors.
nonisolated struct AppearancePreferences: Codable, Sendable, Equatable {
    /// The application default or an override for one wallet, keyed by its recovery identifier.
    enum Scope: Sendable, Hashable {
        case application
        case wallet(UUID)
    }

    private(set) var appThemeID: UUID?
    private(set) var walletThemeIDs: [UUID: UUID] = [:]

    /// Creates preferences that use the original built-in appearance everywhere.
    init() {}

    /// Finds a wallet's override, falling back to the application selection.
    /// - Parameter recoveryID: The wallet's recovery identifier, or `nil` for application appearance.
    /// - Returns: The selected theme identity; `nil` means the original built-in appearance.
    func themeID(for recoveryID: UUID?) -> UUID? {
        recoveryID.flatMap { walletThemeIDs[$0] } ?? appThemeID
    }

    /// Changes one selection without overwriting unrelated wallet preferences.
    /// - Parameters:
    ///   - themeID: A theme identity; `nil` restores the application baseline or removes a wallet override.
    ///   - scope: The selection to change.
    mutating func select(_ themeID: UUID?, for scope: Scope) {
        switch scope {
        case .application: appThemeID = themeID
        case .wallet(let id): walletThemeIDs[id] = themeID
        }
    }

    /// Clears every reference to a removed theme before its deletion is committed.
    /// - Parameter themeID: The deleted custom identity.
    mutating func forget(_ themeID: UUID) {
        if appThemeID == themeID { appThemeID = nil }
        walletThemeIDs = walletThemeIDs.filter { $0.value != themeID }
    }

    /// Removes selections whose themes are no longer available.
    /// - Parameter available: The current custom and built-in identities.
    mutating func reconcile(available: Set<UUID>) {
        if let appThemeID, !available.contains(appThemeID) { self.appThemeID = nil }
        walletThemeIDs = walletThemeIDs.filter { available.contains($0.value) }
    }
}
