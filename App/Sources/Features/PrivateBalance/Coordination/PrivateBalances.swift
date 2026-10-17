import Foundation
import Privacy
import RPC
import Transactions
import Vault
import Wallet

/// Keeps accounts' private-balance keys and notes on this device, syncs each account's notes with its network's
/// provider, and prepares and records its private transactions, for every window.
///
/// Keys are kept by address, and notes by network and address. A notes entry exists only once the account's keys are
/// registered on that network; registration records are permanent and the keys never change, so registration is
/// checked once. Concurrent refreshes and preparations of one account on one network share a sync; other accounts sync
/// in parallel. Recording a transaction's outcome waits for a running sync of the account's notes, and a sync that
/// starts while an outcome is being recorded waits for it, so neither overwrites the other.
/// Every save runs on this actor and is dropped once ``removeAll()`` has run, so an enable or sync that finishes after
/// a reset never brings keys or notes back.
///
/// An unreadable keys or notes item is deleted at most once per launch, during the enable or refresh that reads it:
/// without notes, each account syncs again from the start; without keys, private balances are off until the person
/// turns them on again. If the item is unreadable again in the same launch, the operation throws
/// ``KeychainItemError/unreadable`` and deletes nothing more. A deletion that fails throws its error and is tried again
/// by the next enable or refresh.
actor PrivateBalances: PrivateBalancing {
    /// A network's client, which reads registry records and private notes and proves transfers through the selected
    /// provider.
    typealias Client = any RPC & PrivateNoteProviding & ProofProviding

    /// Each account's keys, by base-58 address.
    typealias Keys = [String: PrivateBalanceKeyRecord]

    /// Each account's notes on each network, by ``noteID(of:on:)``.
    typealias Notes = [String: NoteSyncState]

    /// The stored item that an operation reads or changes.
    nonisolated private enum Item: Hashable, Sendable {
        /// Each account's keys.
        case keys
        /// Each account's notes on each network.
        case notes
    }

    /// What a shared sync found for an account on a network.
    nonisolated private enum SyncOutcome: Sendable {
        /// This device has no keys for the account.
        case off
        /// The selected provider doesn't read private notes on the network.
        case unavailable
        /// The account hasn't registered its keys on the network.
        case unregistered(ShieldedAccount)
        /// The account's notes after the sync, which is saved.
        case synced(ShieldedAccount, NoteSyncState)
    }

    private let recovery: any RecoveryStoring
    private let wallet: any PrivateBalanceKeyDeriving
    private let keys: any ValueStoring<Keys>
    private let notes: any ValueStoring<Notes>
    private let makeClient: @Sendable (Network) -> Client
    private var clients: [Network: Client] = [:]
    private var syncs: [String: Task<SyncOutcome, any Error>] = [:]
    /// The latest outcome that each notes entry is recording, which runs after the entry's earlier recordings and which
    /// a sync of that entry waits for before it loads.
    private var completions: [String: Task<PrivateBalanceStatus, any Error>] = [:]
    /// The deletion of each item found unreadable during this launch, which every later operation that finds the item
    /// unreadable waits for instead of deleting it again.
    private var deletions: [Item: Task<Void, any Error>] = [:]
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
    ///   if cancelled or if ``removeAll()`` ran first, ``KeychainItemError/unreadable`` if an item is unreadable again
    ///   after its deletion this launch, or a storage, derivation, or provider error.
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
            async let savedKeys: Void = update(keys, .keys, from: generation) { $0[address] = record }
            async let savedNotes: Void = update(notes, .notes, from: generation) { $0[id] = $0[id] ?? NoteSyncState() }
            _ = try await (savedKeys, savedNotes)
        case .unregistered?, nil:
            try await update(keys, .keys, from: generation) { $0[address] = record }
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
    ///   `CancellationError` if cancelled or if ``removeAll()`` ran first, ``KeychainItemError/unreadable`` if an item
    ///   is unreadable again after its deletion this launch, or a storage or provider error.
    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus {
        guard ShieldedPool.networks.contains(network) else { return .unavailable }
        return switch try await sharedSync(of: account, on: network) {
        case .off: .off
        case .unavailable: .unavailable
        case .unregistered: .unregistered
        case .synced(_, let state): .lamports(state.lamports)
        }
    }

    /// Builds a private-balance transaction for review after the shared sync of the account's notes.
    ///
    /// Keys are read without authentication. An unregistered account's deposit registers its keys in the same
    /// transaction; its notes sync from the start without being saved, only to learn the output tree. A send reads the
    /// recipient's registry record while the notes sync.
    /// - Parameters:
    ///   - request: The deposit, send, or withdrawal.
    ///   - account: The account that signs and pays.
    ///   - network: The network to run on.
    /// - Returns: The transaction's instructions and the change it makes once it succeeds.
    /// - Throws: ``PrivateBalanceError/unavailable`` on a network or with a provider without private balances, or
    ///   without an output tree; ``PrivateBalanceError/turnedOff`` without keys;
    ///   ``PrivateBalanceError/recipientUnregistered`` for a send to an unregistered account;
    ///   ``PrivateBalanceError/insufficientBalance`` for an unregistered account's send or withdrawal, or notes that
    ///   don't cover the amount; ``PrivateBalanceError/tooManyNotes`` if covering it takes more than 40 notes;
    ///   ``PrivateBalanceError/registeredWithOtherKeys``; a validation error for a zero amount; `CancellationError`;
    ///   or a storage, provider, or proof error.
    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction {
        guard ShieldedPool.networks.contains(network) else { throw PrivateBalanceError.unavailable }
        let client = client(for: network)
        do {
            let outcome: SyncOutcome
            var recipient: Recipient?
            if case .send(_, let destination) = request {
                async let synced = sharedSync(of: account, on: network)
                async let recipients = Recipient.lookup([destination], using: client)
                let found: [Recipient?]
                (outcome, found) = try await (synced, recipients)
                recipient = found.first ?? nil
            } else {
                outcome = try await sharedSync(of: account, on: network)
            }
            let (shielded, state, registers) = try await notes(after: outcome, for: request, client: client)
            let instructions: [Instruction]
            let effect: PreparedPrivateTransaction.Effect
            switch request {
            case .deposit(let lamports):
                guard let treeID = state.outputTreeID else { throw PrivateBalanceError.unavailable }
                let deposit = try ShieldedPool.deposit(lamports: lamports, from: account.address, to: shielded.recipient,
                                                       treeID: treeID)
                instructions = (registers ? [try shielded.register(paidBy: account.address)] : []) + [deposit]
                effect = .deposit(lamports)
            case .send(let lamports, _):
                guard let recipient else { throw PrivateBalanceError.recipientUnregistered }
                let spend = try await state.spend(lamports, to: .transfer(recipient), from: shielded, provider: client)
                (instructions, effect) = ([spend.instruction], .spend(spend))
            case .withdraw(let lamports, let destination):
                let spend = try await state.spend(lamports, to: .withdrawal(destination), from: shielded, provider: client)
                (instructions, effect) = ([spend.instruction], .spend(spend))
            }
            return PreparedPrivateTransaction(instructions: instructions, account: account, network: network,
                                              effect: effect, registers: registers)
        } catch ProviderClientError.unsupportedNetwork, ProviderClientError.privateNotesUnavailable {
            throw PrivateBalanceError.unavailable
        } catch PrivateSpend.ValidationError.insufficientFunds {
            throw PrivateBalanceError.insufficientBalance
        } catch PrivateSpend.ValidationError.tooManyNotes {
            throw PrivateBalanceError.tooManyNotes
        } catch PrivateSpend.ValidationError.noOutputTree {
            throw PrivateBalanceError.unavailable
        }
    }

    /// Records a prepared transaction's settled outcome in the account's notes entry.
    ///
    /// The recording waits for a running sync of the entry and for the entry's earlier recordings, one at a time, and a
    /// sync that starts meanwhile waits for every recording. A succeeded transaction creates the entry if it's missing, such as after the account's first deposit
    /// registered it. Waiting isn't cancellable: once it starts, the recording finishes and saves.
    /// - Parameters:
    ///   - transaction: The transaction from ``prepare(_:from:on:)``.
    ///   - confirmation: The transaction's settled outcome on the same network.
    /// - Returns: The balance after a succeeded transaction; after a failed or dropped one, the saved balance,
    ///   ``PrivateBalanceStatus/unregistered`` without a notes entry, or ``PrivateBalanceStatus/off`` without keys.
    /// - Throws: ``Transactions/ValidationError/invalidTransaction`` for a confirmation from another network,
    ///   `CancellationError` if ``removeAll()`` ran first, ``KeychainItemError/unreadable`` if an item is unreadable
    ///   again after its deletion this launch, or a storage error.
    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus {
        guard confirmation.submission.network == transaction.network else {
            throw Transactions.ValidationError.invalidTransaction
        }
        let generation = generation
        let id = Self.noteID(of: transaction.account, on: transaction.network)
        await settle { syncs[id] }
        let previous = completions[id]
        let completion = Task {
            _ = await previous?.result
            return try await record(transaction, outcome: confirmation.outcome,
                                    signature: confirmation.submission.signature, id: id, from: generation)
        }
        completions[id] = completion
        let result = await completion.result
        if completions[id] == completion { completions[id] = nil }
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

    /// Joins or starts the shared sync of an account's notes on a network.
    ///
    /// Waiting for a running sync isn't cancellable; a cancelled caller gets `CancellationError` once it finishes, and
    /// the shared sync still saves.
    /// - Parameters:
    ///   - account: The account whose notes to sync.
    ///   - network: A network with private balances.
    /// - Returns: What the sync found.
    /// - Throws: `CancellationError` if cancelled, or the sync's error.
    private func sharedSync(of account: Account, on network: Network) async throws -> SyncOutcome {
        let id = Self.noteID(of: account, on: network)
        let sync = syncs[id] ?? Task { try await synced(account, id: id, client: client(for: network)) }
        syncs[id] = sync
        let result = await sync.result
        if syncs[id] == sync { syncs[id] = nil }
        try Task.checkCancellation()
        return try result.get()
    }

    /// Returns the keys, notes, and registration step of a transaction after the shared sync.
    /// - Parameters:
    ///   - outcome: What the shared sync found.
    ///   - request: The transaction.
    ///   - client: The network's client.
    /// - Returns: The account's keys, its notes, and whether the transaction registers the keys first.
    /// - Throws: ``PrivateBalanceError/turnedOff`` without keys, ``PrivateBalanceError/unavailable`` with a provider
    ///   that doesn't read private notes, ``PrivateBalanceError/insufficientBalance`` for an unregistered account's
    ///   send or withdrawal, or a provider error from an unregistered account's unsaved sync.
    private func notes(after outcome: SyncOutcome, for request: PrivateTransactionRequest,
                       client: Client) async throws -> (account: ShieldedAccount, state: NoteSyncState, registers: Bool) {
        switch outcome {
        case .off:
            throw PrivateBalanceError.turnedOff
        case .unavailable:
            throw PrivateBalanceError.unavailable
        case .unregistered(let shielded):
            guard case .deposit = request else { throw PrivateBalanceError.insufficientBalance }
            return (shielded, try await NoteSyncState().synced(for: shielded, using: client), true)
        case .synced(let shielded, let state):
            return (shielded, state, false)
        }
    }

    /// Records a settled outcome in an account's notes entry, unless ``removeAll()`` ran after `generation`.
    /// - Parameters:
    ///   - transaction: The prepared transaction.
    ///   - outcome: Whether it succeeded, failed, or was dropped.
    ///   - signature: The transaction's signature.
    ///   - id: The account's notes entry on the network.
    ///   - generation: The ``generation`` when the completion started.
    /// - Returns: The balance afterward, or why it has none.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`, or a storage error.
    private func record(_ transaction: PreparedPrivateTransaction, outcome: Confirmation.Outcome, signature: String,
                        id: String, from generation: Int) async throws -> PrivateBalanceStatus {
        guard generation == self.generation else { throw CancellationError() }
        guard outcome == .succeeded else {
            async let savedKeys = rebuilding(keys, .keys, from: generation) { try await $0.load() }
            async let savedNotes = rebuilding(notes, .notes, from: generation) { try await $0.load() }
            let (keyRecords, entries) = try await (savedKeys, savedNotes)
            guard keyRecords?[transaction.account.address.value] != nil else { return .off }
            return entries?[id].map { .lamports($0.lamports) } ?? .unregistered
        }
        let effect = transaction.effect
        let recorded = try await update(notes, .notes, from: generation) { entries in
            let saved = entries[id] ?? NoteSyncState()
            let state = switch effect {
            case .deposit(let lamports): try saved.recording(depositOf: lamports, signature: signature)
            case .spend(let spend): try saved.recording(spend, signature: signature)
            }
            entries[id] = state
            return state
        }
        return .lamports(recorded.lamports)
    }

    /// Waits until no task that `running` returns is still running, waiting for each task once.
    /// - Parameter running: Returns the task currently running, if any, such as a notes entry's sync.
    private func settle<Success: Sendable>(_ running: () -> Task<Success, any Error>?) async {
        var settled: Task<Success, any Error>?
        while let task = running(), task != settled {
            settled = task
            _ = await task.result
        }
    }

    /// Syncs an account's notes and saves them, after checking registration if they've never synced.
    ///
    /// The sync waits for an outcome that the notes entry is recording before it loads. A registered account's empty
    /// notes entry is saved before its first sync, so registration is checked once even if that sync fails. A deleted
    /// unreadable notes item has no entries, so every account syncs from the start.
    /// - Parameters:
    ///   - account: The account whose notes to sync.
    ///   - id: The account's notes entry on the network.
    ///   - client: The network's client.
    /// - Returns: The account's keys and notes, or why it has none.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys,
    ///   `CancellationError` if ``removeAll()`` ran first, ``KeychainItemError/unreadable`` if an item is unreadable
    ///   again after its deletion this launch, or a storage or provider error.
    private func synced(_ account: Account, id: String, client: Client) async throws -> SyncOutcome {
        let generation = generation
        await settle { completions[id] }
        async let savedKeys = rebuilding(keys, .keys, from: generation) { try await $0.load() }
        async let savedNotes = rebuilding(notes, .notes, from: generation) { try await $0.load() }
        guard let record = try await savedKeys?[account.address.value] else { return .off }
        let shielded = try record.shieldedAccount(for: account.address)
        do {
            let saved = try await savedNotes?[id]
            if saved == nil {
                switch try await shielded.registration(using: client) {
                case .unregistered: return .unregistered(shielded)
                case .registeredWithOtherKeys: throw PrivateBalanceError.registeredWithOtherKeys
                case .registered:
                    try await update(notes, .notes, from: generation) { $0[id] = $0[id] ?? NoteSyncState() }
                }
            }
            let synced = try await (saved ?? NoteSyncState()).synced(for: shielded, using: client)
            try await update(notes, .notes, from: generation) { $0[id] = synced }
            return .synced(shielded, synced)
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
    ///   - item: The item that `store` keeps.
    ///   - generation: The ``generation`` when the operation started.
    ///   - change: Changes the saved entries, which are empty before any is saved; if it throws, nothing is saved.
    /// - Returns: The change's result.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after the operation started,
    ///   ``KeychainItemError/unreadable`` if the item is unreadable again after its deletion this launch, the change's
    ///   error, or a storage error.
    @discardableResult
    private func update<Entry: Equatable & Sendable, Result: Sendable>(
        _ store: any ValueStoring<[String: Entry]>, _ item: Item, from generation: Int,
        _ change: @escaping @Sendable (inout [String: Entry]) throws -> Result
    ) async throws -> Result {
        guard generation == self.generation else { throw CancellationError() }
        return try await rebuilding(store, item, from: generation) { store in
            try await store.update { saved in
                var entries = saved ?? [:]
                let result = try change(&entries)
                saved = entries
                return result
            }
        }
    }

    /// Runs a storage operation and, if the item is unreadable, deletes it and runs the operation again.
    ///
    /// The item is deleted at most once per launch. An operation that finds it unreadable after the deletion started
    /// waits for that deletion and runs again, so the item is unreadable again only if its bytes were damaged after
    /// the deletion; that second error is thrown. A deletion that fails doesn't count: its error is thrown, and the
    /// next operation that the app starts tries the deletion again.
    /// - Parameters:
    ///   - store: The keys or notes storage.
    ///   - item: The item that `store` keeps.
    ///   - generation: The ``generation`` when the operation started.
    ///   - operation: Reads or changes `store`.
    /// - Returns: The operation's result.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after the operation started, the operation's or the
    ///   deletion's error, or ``KeychainItemError/unreadable`` if the item is unreadable again after its deletion.
    private func rebuilding<Value: Equatable & Sendable, Result: Sendable>(
        _ store: any ValueStoring<Value>, _ item: Item, from generation: Int,
        _ operation: (any ValueStoring<Value>) async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation(store)
        } catch KeychainItemError.unreadable {
            guard generation == self.generation else { throw CancellationError() }
            let deletion = deletions[item] ?? Task.immediate { try await store.delete() }
            deletions[item] = deletion
            let result = await deletion.result
            guard generation == self.generation else { throw CancellationError() }
            if case .failure(let error) = result {
                if deletions[item] == deletion { deletions[item] = nil }
                throw error
            }
            return try await operation(store)
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
