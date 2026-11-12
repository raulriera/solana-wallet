import Foundation
import Privacy
import RPC
import Storage
import Transactions
import Vault
import Wallet

/// Keeps accounts' private-balance keys, notes, and redeem codes on this device, syncs their notes, and prepares and
/// records their private transactions.
actor PrivateBalances: PrivateBalancing {
    /// A network's client for registry records, private notes, and proofs.
    typealias Client = any RPC & PrivateNoteProviding & ProofProviding

    /// Each account's keys, by base-58 address.
    typealias Keys = [String: PrivateBalanceKeyRecord]

    /// Each account's notes on each network, by ``noteID(of:on:)``.
    typealias Notes = [String: NoteSyncState]

    /// Each account's redeem codes on each network, by ``noteID(of:on:)``.
    typealias Codes = [String: RedeemCodeLedger]

    /// The stored item that an operation reads or changes.
    nonisolated enum Item: Hashable, Sendable {
        case keys
        case notes
        case codes
    }

    /// What a shared sync found for an account on a network.
    nonisolated enum SyncOutcome: Sendable {
        /// This device has no keys for the account.
        case off
        /// The selected provider doesn't serve the network.
        case unavailable
        case unregistered(ShieldedAccount)
        case synced(ShieldedAccount, NoteSyncState)
    }

    private let recovery: any RecoveryStoring
    private let wallet: any PrivateBalanceKeyDeriving
    let keys: any ValueStoring<Keys>
    let notes: any ValueStoring<Notes>
    let codes: any ValueStoring<Codes>
    private let makeClient: @Sendable (Network) -> Client
    private var clients: [Network: Client] = [:]
    private var syncs: [String: Task<SyncOutcome, any Error>] = [:]
    /// The latest outcome recording of each notes entry.
    private var completions: [String: Task<PrivateBalanceStatus, any Error>] = [:]
    /// The deletion of each item found unreadable during this launch.
    private var deletions: [Item: Task<Void, any Error>] = [:]
    /// The latest index choice of each codes entry.
    var choices: [String: Task<UInt32, any Error>] = [:]
    /// The number of times ``removeAll()`` ran.
    private(set) var generation = 0

    /// Creates private balances from their storage and clients.
    ///
    /// - Parameters:
    ///   - recovery: The storage of each account's recovery.
    ///   - wallet: Derives private-balance keys from recovery.
    ///   - keys: Device-only storage for each account's keys.
    ///   - notes: Device-only storage for each account's notes on each network.
    ///   - codes: Device-only storage for each account's redeem codes on each network.
    ///   - client: Creates a network's client.
    init(recovery: any RecoveryStoring, wallet: any PrivateBalanceKeyDeriving, keys: any ValueStoring<Keys>,
         notes: any ValueStoring<Notes>, codes: any ValueStoring<Codes>, client: @escaping @Sendable (Network) -> Client) {
        self.recovery = recovery
        self.wallet = wallet
        self.keys = keys
        self.notes = notes
        self.codes = codes
        makeClient = client
    }

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

    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus {
        switch try await sharedSync(of: account, on: network) {
        case .off: try await offStatus(of: account, on: network)
        case .unavailable: .unavailable
        case .unregistered: .unregistered
        case .synced(_, let state): .balance(of: state)
        }
    }

    func savedStatus(of account: Account, on network: Network) async throws -> PrivateBalanceStatus? {
        let generation = generation
        async let savedKeys = rebuilding(keys, .keys, from: generation) { try await $0.load() }
        async let savedNotes = rebuilding(notes, .notes, from: generation) { try await $0.load() }
        guard try await savedKeys?[account.address.value] != nil,
              let state = try await savedNotes?[Self.noteID(of: account, on: network)], state != NoteSyncState()
        else { return nil }
        return .balance(of: state)
    }

    /// Reads the status of an account without keys on this device from the registry.
    ///
    /// - Parameters:
    ///   - account: The account to look up.
    ///   - network: The network of the account's private balance.
    /// - Returns: ``PrivateBalanceStatus/unavailable`` where the selected provider doesn't serve the network, or
    ///   ``PrivateBalanceStatus/off(isRegistered:)`` with whether the registry holds the account's record, `false` if
    ///   it can't be read.
    /// - Throws: An ``RPCProviderError`` other than ``RPCProviderError/invalidKey`` when the selected provider
    ///   can't be used, or `CancellationError` if cancelled.
    private func offStatus(of account: Account, on network: Network) async throws -> PrivateBalanceStatus {
        do {
            let recipients = try await Recipient.lookup([account.address], using: client(for: network))
            return .off(isRegistered: (recipients.first ?? nil) != nil)
        } catch RPCProviderError.unsupportedNetwork {
            return .unavailable
        } catch let error as RPCProviderError where error != .invalidKey {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .off(isRegistered: false)
        }
    }

    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction {
        if case .redeem(let code) = request, code.network != network { throw PrivateBalanceError.codeForOtherNetwork }
        let client = client(for: network)
        do {
            switch request {
            case .deposit, .send, .withdraw:
                return try await preparedTransfer(request, from: account, on: network, client: client)
            case .createCode(let lamports):
                return try await preparedCode(holding: lamports, from: account, on: network, client: client)
            case .redeem(let code):
                return try await preparedRedeem(of: code, into: account, on: network, client: client)
            case .takeBack(let index):
                return try await preparedTakeBack(at: index, into: account, on: network, client: client)
            }
        } catch RPCProviderError.unsupportedNetwork {
            throw PrivateBalanceError.unavailable
        } catch PrivateSpend.ValidationError.insufficientFunds {
            throw PrivateBalanceError.insufficientBalance
        } catch PrivateSpend.ValidationError.tooManyNotes {
            throw PrivateBalanceError.tooManyNotes
        } catch PrivateSpend.ValidationError.noOutputTree {
            throw PrivateBalanceError.unavailable
        } catch is ShieldedPool.TreeError {
            throw PrivateBalanceError.unavailable
        }
    }

    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus {
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

    func removeAll() async throws {
        generation += 1
        async let keysDeletion: Void = keys.delete()
        async let notesDeletion: Void = notes.delete()
        async let codesDeletion: Void = codes.delete()
        _ = try await (keysDeletion, notesDeletion, codesDeletion)
    }

    /// Returns a network's client, creating it the first time the network is used.
    ///
    /// - Parameter network: The network whose client to return.
    /// - Returns: The network's client.
    func client(for network: Network) -> Client {
        if let client = clients[network] { return client }
        let client = makeClient(network)
        clients[network] = client
        return client
    }

    /// Builds a deposit, send, or withdrawal after the shared sync of the account's notes.
    ///
    /// - Parameters:
    ///   - request: The deposit, send, or withdrawal.
    ///   - account: The account that signs and pays.
    ///   - network: The network of the account's private balance.
    ///   - client: The network's client.
    /// - Returns: The prepared transaction.
    /// - Throws: A ``PrivateBalanceError``, or a validation, storage, provider, proof, or cancellation error.
    private func preparedTransfer(_ request: PrivateTransactionRequest, from account: Account, on network: Network,
                                  client: Client) async throws -> PreparedPrivateTransaction {
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
        case .deposit(let amount, let asset):
            guard let treeID = state.outputTreeID else { throw PrivateBalanceError.unavailable }
            let deposit = try asset.deposit(amount, from: account.address, to: shielded.recipient, treeID: treeID)
            instructions = (registers ? [try shielded.register(paidBy: account.address)] : []) + [deposit]
            effect = .deposit(amount, of: asset)
        case .send(let lamports, _):
            guard let recipient else { throw PrivateBalanceError.recipientUnregistered }
            let spend = try await state.spend(lamports, to: .transfer(recipient), from: shielded, rpc: client,
                                              prover: client)
            (instructions, effect) = ([spend.instruction], .spend(spend))
        case .withdraw(let amount, let asset, let owner):
            let destination = asset.withdrawal(to: owner)
            async let opening = Self.opening(destination, paidBy: account.address, client: client)
            let spend = try await state.spend(amount, to: destination, from: shielded, rpc: client, prover: client)
            (instructions, effect) = ([try await opening, spend.instruction].compactMap(\.self), .spend(spend))
        case .createCode, .redeem, .takeBack:
            throw Transactions.ValidationError.invalidTransaction
        }
        return PreparedPrivateTransaction(instructions: instructions, account: account, network: network, effect: effect,
                                          registers: registers, authorities: [.account(account)])
    }

    /// Returns the instruction that opens the token account that a withdrawal pays into, when the account is missing.
    ///
    /// - Parameters:
    ///   - destination: The withdrawal's destination.
    ///   - payer: The account that pays the new account's rent.
    ///   - client: The network's client.
    /// - Returns: The create instruction, or `nil` for a SOL withdrawal or a token account that exists.
    /// - Throws: A validation, provider, or cancellation error.
    private static func opening(_ destination: PrivateSpend.Destination, paidBy payer: Address,
                                client: Client) async throws -> Instruction? {
        guard let tokenAccount = try destination.tokenAccount,
              (try await client.accounts(at: [tokenAccount.value]).value.first ?? nil) == nil else { return nil }
        return try destination.openingTokenAccount(paidBy: payer)
    }

    /// Reads an account's registration where the selected provider can read it.
    ///
    /// - Parameters:
    ///   - account: The account's shielded keys.
    ///   - network: The network whose registry to read.
    /// - Returns: The registration, or `nil` where the provider can't read it.
    /// - Throws: A provider or cancellation error.
    private func registration(of account: ShieldedAccount, on network: Network) async throws -> Registration? {
        do {
            return try await account.registration(using: client(for: network))
        } catch RPCProviderError.unsupportedNetwork {
            return nil
        }
    }

    /// Joins or starts the shared sync of an account's notes on a network.
    ///
    /// - Parameters:
    ///   - account: The account whose notes to sync.
    ///   - network: The network of the account's private balance.
    /// - Returns: What the sync found.
    /// - Throws: `CancellationError` if cancelled, or the sync's error.
    func sharedSync(of account: Account, on network: Network) async throws -> SyncOutcome {
        let id = Self.noteID(of: account, on: network)
        let sync = syncs[id] ?? Task { try await synced(account, id: id, client: client(for: network)) }
        syncs[id] = sync
        let result = await sync.result
        if syncs[id] == sync { syncs[id] = nil }
        try Task.checkCancellation()
        return try result.get()
    }

    /// Returns the keys, notes, and registration step of a transaction after the shared sync.
    ///
    /// - Parameters:
    ///   - outcome: What the shared sync found.
    ///   - request: The requested transaction.
    ///   - client: The network's client.
    /// - Returns: The account's keys, its notes, and whether the transaction registers the keys first.
    /// - Throws: ``PrivateBalanceError/turnedOff``, ``PrivateBalanceError/unavailable``, or
    ///   ``PrivateBalanceError/insufficientBalance`` when the account can't make the transaction, or a provider error.
    func notes(after outcome: SyncOutcome, for request: PrivateTransactionRequest,
                       client: Client) async throws -> (account: ShieldedAccount, state: NoteSyncState, registers: Bool) {
        switch outcome {
        case .off:
            throw PrivateBalanceError.turnedOff
        case .unavailable:
            throw PrivateBalanceError.unavailable
        case .unregistered(let shielded):
            guard case .deposit = request else { throw PrivateBalanceError.insufficientBalance }
            return (shielded, try await NoteSyncState().synced(for: shielded, rpc: client, indexer: client), true)
        case .synced(let shielded, let state):
            return (shielded, state, false)
        }
    }

    /// Records a settled outcome in an account's notes and codes, unless ``removeAll()`` ran after `generation`.
    ///
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
            async let releasedCode: Void = recordCode(of: transaction.effect, outcome: outcome, signature: signature,
                                                      id: id, from: generation)
            let (keyRecords, entries, _) = try await (savedKeys, savedNotes, releasedCode)
            guard keyRecords?[transaction.account.address.value] != nil else { return .off(isRegistered: false) }
            return entries?[id].map(PrivateBalanceStatus.balance(of:)) ?? .unregistered
        }
        let effect = transaction.effect
        async let recordedNotes = update(notes, .notes, from: generation) { entries in
            let saved = entries[id] ?? NoteSyncState()
            let state = switch effect {
            case .deposit(let amount, let asset): try asset.recording(depositOf: amount, in: saved, signature: signature)
            case .spend(let spend), .createCode(let spend, _, _): try saved.recording(spend, signature: signature)
            case .redeem(let redemption): try saved.recording(depositOf: redemption.lamports, signature: signature)
            }
            entries[id] = state
            return state
        }
        async let recordedCodes: Void = recordCode(of: effect, outcome: outcome, signature: signature, id: id,
                                                   from: generation)
        let (recorded, _) = try await (recordedNotes, recordedCodes)
        return .balance(of: recorded)
    }

    /// Waits until no task that `running` returns is still running.
    ///
    /// - Parameter running: Returns the running task, if any.
    private func settle<Success: Sendable>(_ running: () -> Task<Success, any Error>?) async {
        var settled: Task<Success, any Error>?
        while let task = running(), task != settled {
            settled = task
            _ = await task.result
        }
    }

    /// Syncs an account's notes and saves them, after checking registration if they've never synced.
    ///
    /// - Parameters:
    ///   - account: The account whose notes to sync.
    ///   - id: The account's notes entry on the network.
    ///   - client: The network's client.
    /// - Returns: The account's keys and notes, or why it has none.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys``, or a storage, provider, or cancellation error.
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
            let synced = try await (saved ?? NoteSyncState()).synced(for: shielded, rpc: client, indexer: client)
            try await update(notes, .notes, from: generation) { $0[id] = synced }
            return .synced(shielded, synced)
        } catch RPCProviderError.unsupportedNetwork {
            return .unavailable
        }
    }

    /// Changes a store's entries, unless ``removeAll()`` ran after the operation started.
    ///
    /// - Parameters:
    ///   - store: The keys, notes, or codes storage.
    ///   - item: The item that `store` keeps.
    ///   - generation: The ``generation`` when the operation started.
    ///   - change: Changes the saved entries.
    /// - Returns: The change's result.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after the operation started, the change's error, or a
    ///   storage error.
    @discardableResult
    func update<Entry: Equatable & Sendable, Result: Sendable>(
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
    /// - Parameters:
    ///   - store: The keys, notes, or codes storage.
    ///   - item: The item that `store` keeps.
    ///   - generation: The ``generation`` when the operation started.
    ///   - operation: Reads or changes `store`.
    /// - Returns: The operation's result.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after the operation started, the operation's or the
    ///   deletion's error, or ``KeychainItemError/unreadable`` if the item is still unreadable.
    func rebuilding<Value: Equatable & Sendable, Result: Sendable>(
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

    /// Returns the identifier of an account's notes entry on a network.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - network: The network.
    /// - Returns: The network's name, the shielded-pool program's address, and the account's base-58 address.
    static func noteID(of account: Account, on network: Network) -> String {
        "\(network.rawValue)/\(ShieldedPool.id)/\(account.address.value)"
    }
}
