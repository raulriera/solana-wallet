import Foundation
import Observation
import Storage

/// Coordinates one window's RPC provider choices, custom RPCs, and the key entry they need.
@MainActor
@Observable
final class RPCCoordinator: RPCActions {
    /// The screens pushed above RPC.
    var path: [RPCRoute] = []
    /// The custom RPC check of the last opened setup screen.
    private(set) var setup: ProviderSetupModel<CustomRPCError>?
    /// The custom RPC whose details opened last.
    private(set) var details: URL?
    /// The new key's checks of the last opened key screen.
    private(set) var newKey: ProviderSetupModel<RPCConnectionError>?
    /// The custom RPC waiting for the person to confirm its deletion.
    var removal: URL?
    /// The key sheet's checks while a choice waits for a key.
    var keyEntry: ProviderSetupModel<RPCConnectionError>?
    var error: RPCSettingsError?
    /// The ID of the waiting change.
    private(set) var attempt: UUID?
    /// The provider chosen after its key was saved, until another change begins.
    private(set) var completedKeyChoice: RPCSettings.Provider?
    @ObservationIgnored private var request: Request?
    private var keyChoice: KeyChoice?
    private let rpcStore: RPCStore
    private let connection: any ProviderConnecting<RPCConnectionError>
    private let customRPCConnection: any ProviderConnecting<CustomRPCError>

    /// A change that waits for storage.
    private enum Request {
        /// A provider choice, where `afterKeyEntry` marks one that continues after its key was saved.
        case select(RPCSettings.Provider, afterKeyEntry: Bool)
        case remove(URL)
    }

    /// A choice that waits for a key, with the checks of the key sheet it opened.
    private struct KeyChoice: Equatable {
        let provider: RPCSettings.Provider
        let entry: ProviderSetupModel<RPCConnectionError>
    }

    /// Creates a coordinator with the provider services.
    ///
    /// - Parameters:
    ///   - rpcStore: The provider choice, custom RPCs, and key.
    ///   - connection: The connection that checks and saves an API key.
    ///   - customRPCConnection: The connection that checks and adds a custom RPC URL.
    init(rpcStore: RPCStore, connection: any ProviderConnecting<RPCConnectionError>,
         customRPCConnection: any ProviderConnecting<CustomRPCError>) {
        self.rpcStore = rpcStore
        self.connection = connection
        self.customRPCConnection = customRPCConnection
    }

    func select(_ provider: RPCSettings.Provider) {
        begin(.select(provider, afterKeyEntry: false))
    }

    func showDetails(for provider: RPCSettings.Provider) {
        guard attempt == nil else { return }
        switch provider {
        case .helius:
            path.append(.apiKeyDetails)
        case .custom(let url):
            details = url
            path.append(.customRPCDetails)
        case .solana:
            break
        }
    }

    func changeKey() {
        guard attempt == nil else { return }
        newKey = ProviderSetupModel(connection: connection)
        path.append(.apiKey(RPCEntryPurpose(keyPreview: rpcStore.keyPreview)))
    }

    func addCustomRPC() {
        guard attempt == nil else { return }
        setup = ProviderSetupModel(connection: customRPCConnection)
        path.append(.customRPCSetup)
    }

    /// Deletes a confirmed custom RPC.
    ///
    /// - Parameter url: The RPC to delete.
    func remove(_ url: URL) {
        begin(.remove(url))
    }

    /// Continues the choice that asked for a key once the key is saved.
    func keySaved() {
        guard let keyChoice, keyChoice.entry.isSaved else { return }
        self.keyChoice = nil
        begin(.select(keyChoice.provider, afterKeyEntry: true))
    }

    /// Reads the provider settings, and sets an error when they can't be read.
    func load() async {
        await rpcStore.load()
        guard !Task.isCancelled, rpcStore.phase == .unreadable else { return }
        error = .selectionUnreadable
    }

    /// Closes the screens pushed above RPC and any deletion waiting for confirmation.
    func leave() {
        removal = nil
        path = []
    }

    /// Runs the waiting change once.
    ///
    /// - Parameter attempt: The ID of the change to run.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .select(let provider, let afterKeyEntry):
                try await rpcStore.select(provider)
                if afterKeyEntry { completedKeyChoice = provider }
            case .remove(let url):
                try await rpcStore.remove(url)
            }
        } catch is CancellationError {
        } catch RPCProviderError.settingsUnreadable {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            error = .selectionUnreadable
        } catch RPCProviderError.missingKey {
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

    /// Accepts a change unless another one waits.
    ///
    /// - Parameter request: The change to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        completedKeyChoice = nil
        self.request = request
        attempt = UUID()
    }
}
