import Foundation
import Observation
import Storage

/// Owns one window's RPC provider choices, custom RPCs, and the key entry they need, in Settings and onboarding.
@MainActor
@Observable
final class ProvidersCoordinator: ProviderActions {
    /// The screens pushed above Providers; Back removes the last one.
    ///
    /// A closed screen's check or RPC stays until the screen opens again, so the screen keeps its content while it
    /// slides away.
    var path: [ProvidersRoute] = []
    /// The custom RPC check for the last opening of its screen; each opening starts a new one.
    private(set) var setup: ProviderSetupModel<CustomRPCError>?
    /// The custom RPC whose details opened last.
    private(set) var details: URL?
    /// The new key's checks for the last opening of its screen; each opening starts a new one.
    private(set) var newKey: ProviderSetupModel<ProviderConnectionError>?
    /// The custom RPC waiting for the person to confirm its deletion.
    var removal: URL?
    /// The key sheet's checks while a choice waits for a key; each opening starts a new one.
    var keyEntry: ProviderSetupModel<ProviderConnectionError>?
    /// A secret-free error for the alert.
    var error: ProvidersError?
    /// The change waiting for the screen's task, identified without secrets.
    private(set) var attempt: UUID?
    /// The provider chosen once the key it asked for was saved, until another change begins; a choice made without
    /// key entry never sets it.
    private(set) var completedKeyChoice: ProviderSettings.Provider?
    @ObservationIgnored private var request: Request?
    /// The choice that waits for a key; kept after its key sheet closes, so the sheet's saved key still continues it.
    private var keyChoice: KeyChoice?
    private let providers: ProviderStore
    private let connection: any ProviderConnecting<ProviderConnectionError>
    private let customRPCConnection: any ProviderConnecting<CustomRPCError>

    /// A change that waits for storage.
    private enum Request {
        /// Chooses a provider; `afterKeyEntry` marks the choice that continues once its key sheet saved the key.
        case select(ProviderSettings.Provider, afterKeyEntry: Bool)
        case remove(URL)
    }

    /// A choice that waits for a key, with the checks of the key sheet it opened.
    private struct KeyChoice: Equatable {
        let provider: ProviderSettings.Provider
        let entry: ProviderSetupModel<ProviderConnectionError>
    }

    /// Connects the coordinator to the shared provider services.
    /// - Parameters:
    ///   - providers: The provider choice, custom RPCs, and key that every window shares.
    ///   - connection: Verifies and saves the provider's API key.
    ///   - customRPCConnection: Checks a custom RPC URL, then adds it and chooses it.
    init(providers: ProviderStore, connection: any ProviderConnecting<ProviderConnectionError>,
         customRPCConnection: any ProviderConnecting<CustomRPCError>) {
        self.providers = providers
        self.connection = connection
        self.customRPCConnection = customRPCConnection
    }

    /// Chooses the provider that every window uses, asking for its key first when none is saved.
    ///
    /// Taps while another change waits are ignored.
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider) {
        begin(.select(provider, afterKeyEntry: false))
    }

    /// Pushes a provider's details: Helius's saved key or a custom RPC's URL.
    ///
    /// The provider in use stays.
    /// - Parameter provider: The provider whose details to show.
    func showDetails(for provider: ProviderSettings.Provider) {
        guard attempt == nil else { return }
        switch provider {
        case .helius:
            path.append(.providerDetails)
        case .custom(let url):
            details = url
            path.append(.customRPCDetails)
        case .solana:
            break
        }
    }

    /// Pushes the screen that checks a new key and saves it in place of any saved key; the provider in use stays.
    ///
    /// The screen's wording, adding or changing a key, is set when it opens, so it stays while the key saves.
    func changeKey() {
        guard attempt == nil else { return }
        newKey = ProviderSetupModel(connection: connection)
        path.append(.providerKey(ProviderEntryPurpose(keyPreview: providers.keyPreview)))
    }

    /// Opens the screen that checks and adds a custom RPC.
    func addCustomRPC() {
        guard attempt == nil else { return }
        setup = ProviderSetupModel(connection: customRPCConnection)
        path.append(.customRPCSetup)
    }

    /// Deletes a confirmed custom RPC for every window; its details close themselves once the list no longer has it.
    ///
    /// Deleting the RPC in use switches every window to Solana. Taps while another change waits are ignored.
    /// - Parameter url: The RPC to delete.
    func remove(_ url: URL) {
        begin(.remove(url))
    }

    /// Continues the choice that asked for a key, once its key sheet has saved the key; a sheet that closed without a
    /// saved key continues nothing.
    ///
    /// Once the choice is saved, ``completedKeyChoice`` names its provider.
    func keySaved() {
        guard let keyChoice, keyChoice.entry.isSaved else { return }
        self.keyChoice = nil
        begin(.select(keyChoice.provider, afterKeyEntry: true))
    }

    /// Reads the settings that every window shares, unless they were already read; unreadable settings explain the
    /// failure.
    func load() async {
        await providers.load()
        guard !Task.isCancelled, providers.phase == .unreadable else { return }
        error = .selectionUnreadable
    }

    /// Closes the screens pushed above Providers, and any deletion waiting for confirmation, when another Settings
    /// destination opens.
    func leave() {
        removal = nil
        path = []
    }

    /// Closes the coordinator after a reset, dropping pushed screens and what they show, key entry, and any waiting
    /// change or deletion.
    func close() {
        keyChoice = nil
        keyEntry = nil
        setup = nil
        details = nil
        newKey = nil
        removal = nil
        attempt = nil
        request = nil
        completedKeyChoice = nil
        error = nil
        path = []
    }

    /// Runs the waiting change once in the screen's SwiftUI-managed task.
    /// - Parameter attempt: The identifier the screen's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .select(let provider, let afterKeyEntry):
                try await providers.select(provider)
                if afterKeyEntry { completedKeyChoice = provider }
            case .remove(let url):
                try await providers.remove(url)
            }
        } catch is CancellationError {
            // The screen left before the change was saved.
        } catch ProviderClientError.settingsUnreadable {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            error = .selectionUnreadable
        } catch ProviderClientError.missingKey {
            guard !Task.isCancelled, self.attempt == attempt, case .select(let provider, _) = request else { return }
            let keyEntry = ProviderSetupModel(connection: connection)
            keyChoice = KeyChoice(provider: provider, entry: keyEntry)
            self.keyEntry = keyEntry
        } catch {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            switch request {
            case .select: self.error = .selectionUnsaved
            case .remove: self.error = .deletionUnsaved
            }
        }
    }

    /// Accepts one change at a time, ignoring taps while another change waits.
    /// - Parameter request: The change to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        completedKeyChoice = nil
        self.request = request
        attempt = UUID()
    }
}
