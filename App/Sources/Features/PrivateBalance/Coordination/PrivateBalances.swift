import Foundation
import Privacy
import RPC
import Transactions
import Vault
import Wallet

/// Keeps accounts' private-balance keys and notes on this device and syncs each account's notes with its network's
/// provider, for every window.
///
/// Keys are kept by address, and notes by network and address. A notes entry exists only once the account's keys are
/// registered on that network; registration records are permanent and the keys never change, so registration is
/// checked once. Concurrent refreshes of one account on one network share a sync; other accounts sync in parallel.
/// Every save runs on this actor and is dropped once ``removeAll()`` has run, so an enable or sync that finishes after
/// a reset never brings keys or notes back.
actor PrivateBalances: PrivateBalancing {
    /// A network's client, which reads registry records and private notes through the selected provider.
    typealias Client = any RPC & PrivateNoteProviding

    /// Each account's keys, by base-58 address.
    typealias Keys = [String: PrivateBalanceKeyRecord]

    /// Each account's notes on each network, by ``noteID(of:on:)``.
    typealias Notes = [String: NoteSyncState]

    private let recovery: any RecoveryStoring
    private let wallet: any PrivateBalanceKeyDeriving
    private let keys: any ValueStoring<Keys>
    private let notes: any ValueStoring<Notes>
    private let makeClient: @Sendable (Network) -> Client
    private var clients: [Network: Client] = [:]
    private var syncs: [String: Task<PrivateBalanceStatus, any Error>] = [:]
    /// Advances each time ``removeAll()`` runs, so an operation that started earlier saves nothing.
    private var generation = 0

    /// Connects private balances to the stores and providers that every window shares.
    /// - Parameters:
    ///   - recovery: The protected storage whose recovery derives an account's keys.
    ///   - wallet: Derives private-balance keys from recovery.
    ///   - keys: Device-only storage for each account's keys.
    ///   - notes: Device-only storage for each account's notes on each network.
    ///   - client: Creates a network's client the first time that network is used.
    init(recovery: any RecoveryStoring, wallet: any PrivateBalanceKeyDeriving, keys: any ValueStoring<Keys>,
         notes: any ValueStoring<Notes>, client: @escaping @Sendable (Network) -> Client) {
        self.recovery = recovery
        self.wallet = wallet
        self.keys = keys
        self.notes = notes
        makeClient = client
    }

    /// Derives an account's private-balance keys from its recovery and keeps them on this device.
    ///
    /// The registration check runs only where the selected provider can read the registry on a network with private
    /// balances; elsewhere, such as with a custom RPC off mainnet, the keys are kept unchecked and a later refresh
    /// checks registration first. Keys that are already registered keep the account's empty notes entry beside them.
    /// - Parameters:
    ///   - account: The account whose keys to keep.
    ///   - network: The network whose registration to check.
    /// - Throws: ``PrivateBalanceError/unsupportedAccount`` for an account without private-balance keys,
    ///   ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys, `CancellationError`
    ///   if cancelled or if ``removeAll()`` ran first, or a storage, derivation, or provider error.
    func enable(_ account: Account, on network: Network) async throws {
        guard account.path.hasPrivateBalanceKeys else { throw PrivateBalanceError.unsupportedAccount }
        let generation = generation
        let recovery = try await recovery.recovery(for: account.recoveryID,
                                                   reason: String(localized: "Turn on private balances"))
        let record = PrivateBalanceKeyRecord(try await wallet.privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        ))
        let address = account.address.value
        switch try await registration(of: record.shieldedAccount(for: account.address), on: network) {
        case .registeredWithOtherKeys?:
            throw PrivateBalanceError.registeredWithOtherKeys
        case .registered?:
            let id = Self.noteID(of: account, on: network)
            async let savedKeys: Void = update(keys, from: generation) { $0[address] = record }
            async let savedNotes: Void = update(notes, from: generation) { $0[id] = $0[id] ?? NoteSyncState() }
            _ = try await (savedKeys, savedNotes)
        case .unregistered?, nil:
            try await update(keys, from: generation) { $0[address] = record }
        }
    }

    /// Reads an account's new and spent private notes on a network and returns its balance.
    ///
    /// A refresh that's already running for the account on the network is shared. Waiting for it isn't
    /// cancellable; a cancelled caller gets `CancellationError` once it finishes, and the shared sync still saves.
    /// - Parameters:
    ///   - account: The account whose balance to refresh.
    ///   - network: The network to read.
    /// - Returns: ``PrivateBalanceStatus/off`` without keys; ``PrivateBalanceStatus/unavailable`` on a network
    ///   without private balances, or with a provider that doesn't read them there; ``PrivateBalanceStatus/unregistered``
    ///   before the keys are registered; else the balance.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys,
    ///   `CancellationError` if cancelled or if ``removeAll()`` ran first, or a storage or provider error.
    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus {
        guard ShieldedPool.networks.contains(network) else { return .unavailable }
        let id = Self.noteID(of: account, on: network)
        let sync = syncs[id] ?? Task { try await status(of: account, id: id, client: client(for: network)) }
        syncs[id] = sync
        let result = await sync.result
        if syncs[id] == sync { syncs[id] = nil }
        try Task.checkCancellation()
        return try result.get()
    }

    /// Deletes every account's private-balance keys and notes, both at once.
    ///
    /// An enable or refresh that started earlier saves nothing afterward: its saves are dropped, and a save that
    /// already reached storage runs before these deletions.
    /// - Throws: A storage or cancellation error.
    func removeAll() async throws {
        generation += 1
        async let keysDeletion: Void = keys.delete()
        async let notesDeletion: Void = notes.delete()
        _ = try await (keysDeletion, notesDeletion)
    }

    /// Returns a network's client, creating it the first time the network is used.
    /// - Parameter network: The network whose client to return.
    /// - Returns: The client that every refresh on the network shares.
    private func client(for network: Network) -> Client {
        if let client = clients[network] { return client }
        let client = makeClient(network)
        clients[network] = client
        return client
    }

    /// Reads an account's registration where the selected provider can read it.
    /// - Parameters:
    ///   - account: The account's shielded keys.
    ///   - network: The network whose registry to read.
    /// - Returns: The registration, or `nil` on a network without private balances or with a custom RPC that
    ///   doesn't serve the network.
    /// - Throws: A provider or cancellation error.
    private func registration(of account: ShieldedAccount, on network: Network) async throws -> Registration? {
        guard ShieldedPool.networks.contains(network) else { return nil }
        do {
            return try await account.registration(using: client(for: network))
        } catch ProviderClientError.unsupportedNetwork {
            return nil
        }
    }

    /// Syncs an account's notes and saves them, after checking registration if they've never synced.
    ///
    /// A registered account's empty notes entry is saved before its first sync, so registration is checked once
    /// even if that sync fails.
    /// - Parameters:
    ///   - account: The account whose notes to sync.
    ///   - id: The account's notes entry on the network.
    ///   - client: The network's client.
    /// - Returns: The account's balance, or why it has none.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys,
    ///   `CancellationError` if ``removeAll()`` ran first, or a storage or provider error.
    private func status(of account: Account, id: String, client: Client) async throws -> PrivateBalanceStatus {
        let generation = generation
        async let savedKeys = keys.load()
        async let savedNotes = notes.load()
        guard let record = try await savedKeys?[account.address.value] else { return .off }
        let shielded = try record.shieldedAccount(for: account.address)
        do {
            let saved = try await savedNotes?[id]
            if saved == nil {
                switch try await shielded.registration(using: client) {
                case .unregistered: return .unregistered
                case .registeredWithOtherKeys: throw PrivateBalanceError.registeredWithOtherKeys
                case .registered: try await update(notes, from: generation) { $0[id] = $0[id] ?? NoteSyncState() }
                }
            }
            let synced = try await (saved ?? NoteSyncState()).synced(for: shielded, using: client)
            try await update(notes, from: generation) { $0[id] = synced }
            return .lamports(synced.lamports)
        } catch ProviderClientError.unsupportedNetwork, ProviderClientError.privateNotesUnavailable {
            return .unavailable
        }
    }

    /// Changes a store's entries, unless ``removeAll()`` ran after the operation started.
    ///
    /// The check and the start of the change run on this actor without suspending in between, so a deletion that
    /// ``removeAll()`` starts later runs after the change.
    /// - Parameters:
    ///   - store: The keys or notes storage.
    ///   - generation: The ``generation`` when the operation started.
    ///   - change: Changes the saved entries, which are empty before any is saved.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after the operation started, or a storage error.
    private func update<Entry: Equatable & Sendable>(
        _ store: any ValueStoring<[String: Entry]>, from generation: Int,
        _ change: @escaping @Sendable (inout [String: Entry]) -> Void
    ) async throws {
        guard generation == self.generation else { throw CancellationError() }
        try await store.update { saved in
            var entries = saved ?? [:]
            change(&entries)
            saved = entries
        }
    }

    /// Names an account's notes entry on a network.
    /// - Parameters:
    ///   - account: The account.
    ///   - network: The network.
    /// - Returns: The network's name and the account's base-58 address.
    static func noteID(of account: Account, on network: Network) -> String {
        "\(network.rawValue)/\(account.address.value)"
    }
}
