import Foundation
import Observation
import SwiftUI

/// Owns one window's RPC provider choices, custom RPCs, and the key entry they need, in Settings and onboarding.
@MainActor
@Observable
final class ProvidersCoordinator: ProviderActions {
    /// The provider in use as last read, or `nil` before the first read, so no provider shows as in use.
    private(set) var selection: ProviderSettings.Provider?
    /// The custom RPCs as last read, in the order they were added.
    private(set) var customRPCs: [URL] = []
    /// The screens pushed above Providers; Back removes the last one.
    ///
    /// A closed screen's check or RPC stays until the screen opens again, so the screen keeps its content while it
    /// slides away.
    var path: [ProvidersRoute] = []
    /// The custom RPC check for the last opening of its screen; each opening starts a new one.
    private(set) var setup: ProviderSubmission<CustomRPCError>?
    /// The custom RPC whose details opened last.
    private(set) var details: URL?
    /// The saved key as last read, with all but its first four characters masked, or `nil` when no key is saved; the
    /// full key is never kept.
    private(set) var keyPreview: String?
    /// The new key's checks for the last opening of its screen; each opening starts a new one.
    private(set) var newKey: ProviderSubmission<ProviderConnectionError>?
    /// The custom RPC waiting for the person to confirm its deletion.
    var removal: URL?
    /// The key sheet's checks while a choice waits for a key; each opening starts a new one.
    var keyEntry: ProviderSubmission<ProviderConnectionError>?
    /// A secret-free error for the alert.
    var error: ProvidersError?
    /// The change waiting for the screen's task, identified without secrets.
    private(set) var attempt: UUID?
    /// Tells every window when a provider change applies, including a saved key.
    let revision: Revision
    @ObservationIgnored private var request: Request?
    /// The choice that waits for a key; kept after its key sheet closes, so the sheet's saved key still continues it.
    private var keyChoice: KeyChoice?
    private let providers: any ProviderSelecting
    private let providerKey: any ValueStoring<String>
    private let connection: any ProviderConnecting<ProviderConnectionError>
    private let customRPCConnection: any ProviderConnecting<CustomRPCError>

    /// A change that waits for storage.
    private enum Request {
        case select(ProviderSettings.Provider)
        case remove(URL)
    }

    /// A choice that waits for a key, with the checks of the key sheet it opened.
    private struct KeyChoice: Equatable {
        let provider: ProviderSettings.Provider
        let entry: ProviderSubmission<ProviderConnectionError>
    }

    /// Connects the coordinator to the shared provider services.
    /// - Parameters:
    ///   - providers: Reads and changes the provider that every window uses, and the custom RPCs.
    ///   - providerKey: Device-only storage for Helius's accepted key, read only to show its first characters.
    ///   - connection: Verifies and saves the provider's API key.
    ///   - customRPCConnection: Checks a custom RPC URL, then adds it and chooses it.
    ///   - revision: Tells every window when a provider change applies.
    init(providers: any ProviderSelecting, providerKey: any ValueStoring<String>,
         connection: any ProviderConnecting<ProviderConnectionError>,
         customRPCConnection: any ProviderConnecting<CustomRPCError>, revision: Revision) {
        self.providers = providers
        self.providerKey = providerKey
        self.connection = connection
        self.customRPCConnection = customRPCConnection
        self.revision = revision
    }

    /// Chooses the provider that every window uses, asking for its key first when none is saved.
    ///
    /// Taps while another change waits are ignored.
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider) {
        begin(.select(provider))
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
        newKey = ProviderSubmission(connection: connection)
        path.append(.providerKey(ProviderEntryPurpose(keyPreview: keyPreview)))
    }

    /// Opens the screen that checks and adds a custom RPC.
    func addCustomRPC() {
        guard attempt == nil else { return }
        setup = ProviderSubmission(connection: customRPCConnection)
        path.append(.customRPCSetup)
    }

    /// Deletes a confirmed custom RPC for every window; its details close themselves once the list no longer has it.
    ///
    /// Deleting the RPC in use switches every window to Solana. Taps while another change waits are ignored.
    /// - Parameter url: The RPC to delete.
    func remove(_ url: URL) {
        begin(.remove(url))
    }

    /// Whether the key sheet that a waiting choice opened has saved its key, so the choice can continue.
    var isKeyChoiceSaved: Bool { keyChoice?.entry.isSaved ?? false }

    /// Continues the choice that asked for a key, once its key sheet has saved the key; a sheet that closed without a
    /// saved key continues nothing.
    func keySaved() {
        guard isKeyChoiceSaved, let provider = keyChoice?.provider else { return }
        keyChoice = nil
        select(provider)
    }

    /// Reads the saved choice, custom RPCs, and key again; unreadable settings keep the last ones read and explain
    /// the failure.
    ///
    /// The key is read separately and only its first characters are kept; a key that can't be read keeps the last
    /// preview without an alert, because no choice depends on it.
    func reload() async {
        do {
            let settings = try await providers.settings()
            guard !Task.isCancelled else { return }
            selection = settings.selection
            // Rows animate in and out with the change that adds or deletes them.
            withAnimation { customRPCs = settings.customRPCs }
        } catch is CancellationError {
            // The screen left before the settings were read.
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .selectionUnreadable
        }
        do {
            let key = try await providerKey.load()
            guard !Task.isCancelled else { return }
            keyPreview = key?.formatted(.masked)
        } catch {
            // A key that can't be read keeps the last preview.
        }
    }

    /// Closes the screens pushed above Providers, and any deletion waiting for confirmation, when another Settings
    /// destination opens.
    func leave() {
        removal = nil
        path = []
    }

    /// Closes the coordinator after a reset, dropping pushed screens and what they show, key entry, any waiting change
    /// or deletion, and the settings and key preview last read.
    func close() {
        keyChoice = nil
        keyEntry = nil
        setup = nil
        details = nil
        newKey = nil
        removal = nil
        attempt = nil
        request = nil
        error = nil
        selection = nil
        customRPCs = []
        keyPreview = nil
        path = []
    }

    /// Runs the waiting change once in the screen's SwiftUI-managed task.
    /// - Parameter attempt: The identifier the screen's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .select(let provider): try await providers.select(provider)
            case .remove(let url): try await providers.remove(url)
            }
        } catch is CancellationError {
            // The screen left before the change was saved.
        } catch ProviderClientError.missingKey {
            guard !Task.isCancelled, self.attempt == attempt, case .select(let provider) = request else { return }
            let keyEntry = ProviderSubmission(connection: connection)
            keyChoice = KeyChoice(provider: provider, entry: keyEntry)
            self.keyEntry = keyEntry
        } catch {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            switch request {
            case .select(let provider) where provider == selection:
                // Choosing the provider in use changes nothing, even when its key can't be read.
                break
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
        self.request = request
        attempt = UUID()
    }
}
