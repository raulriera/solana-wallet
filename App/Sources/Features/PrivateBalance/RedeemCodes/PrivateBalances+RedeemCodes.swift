import Foundation
import Privacy
import RPC
import Transactions
import Wallet

/// Redeem codes: an account moves private SOL into a one-time account at an index of its code root, and anyone with the
/// code sweeps that account into a private balance.
///
/// A code's one-time account receives one private note and a public reserve that pays for redeeming it: a registration
/// record's rent, two signatures, and one nullifier's tree fee. A redeem or take-back spends the note to the receiving
/// account, registers that account first if it needs it, and deposits the rest of the reserve, so the one-time account
/// pays every cost and ends at exactly zero lamports. Whether a code is outstanding comes from the indexer: a code
/// whose notes are all spent was redeemed or taken back, whatever its one-time account's public lamports.
///
/// Each account's codes entry keeps its codes, the indices of prepared codes whose fundings aren't recorded, and its
/// next index. A new code takes the first index above the highest one that the indexer shows used in a batch of
/// ``RedeemCodeScan/choiceBatchSize`` from the next index; the entry keeps the index pending before the preparation
/// returns, so no later code reuses it, even after the app quits before the funding's outcome is recorded. Choices of one entry run one at a time.
extension PrivateBalances {
    /// Lists the account's redeem codes that the indexer doesn't show as spent, dropping codes that were redeemed or
    /// taken back.
    ///
    /// The keys and the codes entry are read together. Without a codes entry, or with one that this device started
    /// without a scan, such as after a restore, the account's one-time accounts are scanned in batches of
    /// ``RedeemCodeScan/discoveryBatchSize`` from index 0 until a batch has none used; the codes with unspent notes
    /// join the entry, each with its notes' amount and its one-time account's lamports as the reserve. Then each code's and pending index's one-time account syncs from the
    /// start, concurrently, while the pending indices' one-time accounts' lamports are read: a code with unspent notes
    /// is outstanding with their amount; a code whose funding the indexer doesn't report yet stays outstanding; a code
    /// whose notes are all spent leaves. A pending index with unspent notes becomes a code, such as one whose app quit
    /// before recording its funding, and one without them leaves once its funding can no longer land.
    /// - Parameters:
    ///   - account: The account that created the codes.
    ///   - network: The network that holds them.
    /// - Returns: The outstanding codes, by index.
    /// - Throws: ``PrivateBalanceError/unavailable`` on a network or with a provider without private balances,
    ///   ``PrivateBalanceError/turnedOff`` without keys, `CancellationError` if cancelled or if ``removeAll()`` ran
    ///   first, ``KeychainItemError/unreadable`` if an item is unreadable again after its deletion this launch, or a
    ///   storage or provider error.
    func outstandingCodes(of account: Account, on network: Network) async throws -> [OutstandingRedeemCode] {
        guard ShieldedPool.networks.contains(network) else { throw PrivateBalanceError.unavailable }
        let generation = generation
        let client = client(for: network)
        let id = Self.noteID(of: account, on: network)
        async let savedKeys = keyRecord(of: account, from: generation)
        async let savedCodes = rebuilding(codes, .codes, from: generation) { try await $0.load() }
        do {
            guard let keys = try await savedKeys else { throw PrivateBalanceError.turnedOff }
            var ledger = try await savedCodes?[id]
            if ledger?.isDiscovered != true {
                let discovered = try await discoveredLedger(from: keys, client: client)
                ledger = try await update(codes, .codes, from: generation) { entries in
                    var merged = entries[id] ?? RedeemCodeLedger(isDiscovered: true)
                    merged.merge(discovered)
                    entries[id] = merged
                    return merged
                }
            }
            guard var reconciled = ledger else { return [] }
            let pending = reconciled.pending.map(\.index)
            let addresses = try pending.map { try keys.oneTimeAddress(at: $0) }
            let indices = (reconciled.records.map(\.index) + pending).sorted()
            async let statuses = RedeemCodeScan.statuses(of: indices, from: keys, using: client)
            async let balances = Self.lamports(of: addresses, using: client)
            let (found, lamports) = try await (statuses, balances)
            let reserves = Dictionary(uniqueKeysWithValues: zip(pending, lamports))
            let now = Date.now
            reconciled.reconcile(with: found, reserves: reserves, at: now)
            if reconciled != ledger {
                let local = reconciled
                reconciled = try await update(codes, .codes, from: generation) { entries in
                    entries[id]?.reconcile(with: found, reserves: reserves, at: now)
                    return entries[id] ?? local
                }
            }
            return try reconciled.records.map { record in
                OutstandingRedeemCode(record: record, code: try RedeemCode(
                    secret: keys.oneTimeAccount(at: record.index).secret, network: network
                ))
            }
        } catch ProviderClientError.unsupportedNetwork, ProviderClientError.privateNotesUnavailable {
            throw PrivateBalanceError.unavailable
        }
    }

    /// Builds the spend that funds a new code: the amount as a private note to the code's one-time account, and its
    /// reserve as a public withdrawal to the same account.
    ///
    /// The account's notes sync and the rent is read while the keys are read; the code's index is chosen while the
    /// notes sync, and the output tree's fee is read after the sync. The chosen index is pending in the codes entry
    /// before this returns, and stays pending until ``complete(_:with:)`` records the funding's outcome, or until it
    /// expires if the funding is never submitted; either way, no later code takes it.
    /// - Parameters:
    ///   - lamports: The code's private amount.
    ///   - account: The account that creates the code, signs, and pays.
    ///   - network: A network with private balances.
    ///   - client: The network's client.
    /// - Returns: The spend, which the account alone signs.
    /// - Throws: The errors of ``prepare(_:from:on:)`` before they're mapped to private-balance errors.
    func preparedCode(holding lamports: UInt64, from account: Account, on network: Network,
                      client: Client) async throws -> PreparedPrivateTransaction {
        guard lamports > 0 else { throw Transactions.ValidationError.invalidAmount }
        let generation = generation
        let id = Self.noteID(of: account, on: network)
        async let synced = sharedSync(of: account, on: network)
        async let rent = ShieldedPool.registryRecordRent(using: client)
        guard let keys = try await keyRecord(of: account, from: generation) else { throw PrivateBalanceError.turnedOff }
        async let chosenIndex = heldIndex(of: id, from: keys, generation: generation, client: client)
        let (shielded, state, _) = try await notes(after: synced, for: .createCode(lamports), client: client)
        guard let treeID = state.outputTreeID else { throw PrivateBalanceError.unavailable }
        async let treeFee = ShieldedPool.feePerNullifier(treeID: treeID, using: client)
        let reserve = try Redemption.reserve(rent: try await rent, treeFee: try await treeFee)
        let index = try await chosenIndex
        let recipient = try keys.oneTimeAccount(at: index).shieldedAccount.recipient
        let spend = try await state.spend(lamports, to: .fundedTransfer(recipient, publicLamports: reserve),
                                          from: shielded, provider: client)
        return PreparedPrivateTransaction(instructions: [spend.instruction], account: account, network: network,
                                          effect: .createCode(spend, index: index, reserve: reserve), registers: false,
                                          authorities: [.account(account)])
    }

    /// Builds the redeem of a code into an account's private balance.
    ///
    /// The receiving account's keys are read while the code's one-time account is derived.
    /// - Parameters:
    ///   - code: The code, on `network`.
    ///   - account: The account that receives the code's SOL.
    ///   - network: A network with private balances.
    ///   - client: The network's client.
    /// - Returns: The sweep, which the code's one-time account signs and pays for.
    /// - Throws: ``PrivateBalanceError/turnedOff`` without keys, or the errors of
    ///   ``preparedRedemption(of:into:keys:on:takingBack:client:)``.
    func preparedRedeem(of code: RedeemCode, into account: Account, on network: Network,
                        client: Client) async throws -> PreparedPrivateTransaction {
        async let savedKeys = keyRecord(of: account, from: generation)
        let oneTime = try OneTimeAccount(secret: code.secret)
        guard let keys = try await savedKeys else { throw PrivateBalanceError.turnedOff }
        return try await preparedRedemption(of: oneTime, into: account, keys: keys, on: network, takingBack: nil,
                                            client: client)
    }

    /// Builds the take-back of one of the account's own codes into its private balance, reading its keys once.
    /// - Parameters:
    ///   - index: The code's index under the account's code root.
    ///   - account: The account that created the code.
    ///   - network: A network with private balances.
    ///   - client: The network's client.
    /// - Returns: The sweep, which the code's one-time account signs and pays for.
    /// - Throws: ``PrivateBalanceError/turnedOff`` without keys, or the errors of
    ///   ``preparedRedemption(of:into:keys:on:takingBack:client:)``.
    func preparedTakeBack(at index: UInt32, into account: Account, on network: Network,
                          client: Client) async throws -> PreparedPrivateTransaction {
        guard let keys = try await keyRecord(of: account, from: generation) else { throw PrivateBalanceError.turnedOff }
        return try await preparedRedemption(of: keys.oneTimeAccount(at: index), into: account, keys: keys, on: network,
                                            takingBack: index, client: client)
    }

    /// Builds the sweep of a code's one-time account into an account's private balance.
    ///
    /// The one-time account's notes sync from the start without being saved, while the receiving account's shared
    /// sync, the one-time account's finalized lamports, and the receiving account's registration cost are read. After
    /// the spend is proved, the fee per nullifier of the tree that holds the notes it spends is read. An unregistered
    /// account is registered first, paid by the one-time account, and also signs. The trailing deposit holds every
    /// lamport left before the network fee, which ``TransactionCoordinating/simulate(_:)`` charges.
    /// - Parameters:
    ///   - oneTime: The code's one-time account.
    ///   - account: The account that receives the code's SOL.
    ///   - keys: The receiving account's kept keys.
    ///   - network: A network with private balances.
    ///   - index: The index of the account's own code that this takes back, or `nil` for a redeem.
    ///   - client: The network's client.
    /// - Returns: The sweep, which the one-time account signs and pays for.
    /// - Throws: ``PrivateBalanceError/codeRedeemed`` if the one-time account holds no lamports,
    ///   ``PrivateBalanceError/codeNotReady`` if it holds lamports but the indexer reports no notes yet,
    ///   ``PrivateBalanceError/codeUnderfunded`` if its lamports don't cover the registration and the tree fees,
    ///   ``PrivateBalanceError/turnedOff`` if the receiving account's keys were removed meanwhile, or the errors of
    ///   ``prepare(_:from:on:)`` before they're mapped to private-balance errors.
    func preparedRedemption(of oneTime: OneTimeAccount, into account: Account, keys: PrivateBalanceKeyRecord,
                            on network: Network, takingBack index: UInt32?,
                            client: Client) async throws -> PreparedPrivateTransaction {
        let shielded = try keys.shieldedAccount(for: account.address)
        let code = try oneTime.shieldedAccount
        async let codeNotes = NoteSyncState().synced(for: code, using: client)
        async let synced = sharedSync(of: account, on: network)
        async let balances = Self.lamports(of: [code.signingAddress], using: client)
        async let cost = shielded.registrationCost(using: client)
        let (state, outcome, lamports, registrationCost) = try await (codeNotes, synced, balances, cost)
        guard let balance = lamports.first, balance > 0 else { throw PrivateBalanceError.codeRedeemed }
        guard !state.notes.isEmpty else { throw PrivateBalanceError.codeNotReady }
        guard let outputTree = state.outputTreeID else { throw PrivateBalanceError.unavailable }
        let registers = switch outcome {
        case .off: throw PrivateBalanceError.turnedOff
        case .unavailable: throw PrivateBalanceError.unavailable
        case .unregistered: true
        case .synced: false
        }
        let recipient = try shielded.recipient
        let spend = try await state.spend(state.lamports, to: .transfer(recipient), from: code, provider: client)
        let treeFee = try await ShieldedPool.feePerNullifier(treeID: spend.inputTreeID, using: client)
        let available = try Redemption.availableLamports(of: balance, registrationCost: registers ? registrationCost : 0,
                                                         treeFee: treeFee, nullifierCount: spend.nullifierCount)
        let registration = registers ? [try shielded.register(paidBy: code.signingAddress)] : []
        let redemption = try Redemption(instructions: registration + [spend.instruction], noteLamports: spend.lamports,
                                        availableLamports: available, source: code.signingAddress, recipient: recipient,
                                        treeID: outputTree, takenBackIndex: index)
        return PreparedPrivateTransaction(instructions: try redemption.transactionInstructions, account: account,
                                          network: network, effect: .redeem(redemption), registers: registers,
                                          authorities: [.oneTime(oneTime)] + (registers ? [.account(account)] : []))
    }

    /// Records a settled transaction's change to the account's codes entry: a created code joins it, a code taken back
    /// leaves it, and a code whose funding failed or was dropped leaves the pending indices. Other transactions change
    /// nothing.
    /// - Parameters:
    ///   - effect: The transaction's effect.
    ///   - outcome: Whether it succeeded, failed, or was dropped.
    ///   - signature: The transaction's signature.
    ///   - id: The account's codes entry on the network.
    ///   - generation: The ``generation`` when the completion started.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`, or a storage error.
    func recordCode(of effect: PreparedPrivateTransaction.Effect, outcome: Confirmation.Outcome, signature: String,
                    id: String, from generation: Int) async throws {
        switch (effect, outcome) {
        case (.createCode(let spend, let index, let reserve), .succeeded):
            let record = RedeemCodeRecord(index: index, amount: spend.lamports, reserve: reserve, created: .now,
                                          fundingSignature: signature)
            try await update(codes, .codes, from: generation) { entries in
                var ledger = entries[id] ?? RedeemCodeLedger(isDiscovered: false)
                ledger.add(record)
                entries[id] = ledger
            }
        case (.createCode(_, let index, _), _):
            try await update(codes, .codes, from: generation) { $0[id]?.release(index) }
        case (.redeem(let redemption), .succeeded):
            guard let index = redemption.takenBackIndex else { return }
            try await update(codes, .codes, from: generation) { $0[id]?.remove([index]) }
        case (.redeem, _), (.deposit, _), (.spend, _):
            return
        }
    }

    /// Chooses the index of a new code after the entry's earlier choices, and keeps it pending in the codes entry.
    ///
    /// The choice runs to its end even if the caller is cancelled, so its index is pending either way.
    /// - Parameters:
    ///   - id: The account's codes entry on the network.
    ///   - keys: The account's kept keys.
    ///   - generation: The ``generation`` when the preparation started.
    ///   - client: The network's client.
    /// - Returns: The pending index.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`,
    ///   ``Wallet/OneTimeAccountError/invalidIndex`` once every index is used, or a storage, derivation, or provider
    ///   error.
    private func heldIndex(of id: String, from keys: PrivateBalanceKeyRecord, generation: Int,
                           client: Client) async throws -> UInt32 {
        let previous = choices[id]
        let choice = Task {
            _ = await previous?.result
            return try await chosenIndex(of: id, from: keys, generation: generation, client: client)
        }
        choices[id] = choice
        let result = await choice.result
        if choices[id] == choice { choices[id] = nil }
        return try result.get()
    }

    /// Chooses the index of a new code and keeps it pending: the first index above the highest used one in the first
    /// batch from the entry's next index that isn't wholly used.
    ///
    /// The entry's next index is above every recorded and pending code, so a choice never takes the index of a code
    /// whose funding the indexer doesn't report yet.
    /// - Parameters:
    ///   - id: The account's codes entry on the network.
    ///   - keys: The account's kept keys.
    ///   - generation: The ``generation`` when the preparation started.
    ///   - client: The network's client.
    /// - Returns: The pending index.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`,
    ///   ``Wallet/OneTimeAccountError/invalidIndex`` once every index is used, or a storage, derivation, or provider
    ///   error.
    private func chosenIndex(of id: String, from keys: PrivateBalanceKeyRecord, generation: Int,
                             client: Client) async throws -> UInt32 {
        let start = try await rebuilding(codes, .codes, from: generation) { try await $0.load() }?[id]?.nextIndex ?? 0
        var candidates = RedeemCodeScan.candidates(from: start, count: RedeemCodeScan.choiceBatchSize)
        while let last = candidates.last {
            let used = try await RedeemCodeScan.fundings(of: candidates, from: keys, using: client).map(\.index)
            if let index = RedeemCodeScan.choice(in: candidates, used: Set(used)) {
                let code = PendingRedeemCode(index: index, created: .now)
                try await update(codes, .codes, from: generation) { entries in
                    var ledger = entries[id] ?? RedeemCodeLedger(isDiscovered: false)
                    ledger.hold(code)
                    entries[id] = ledger
                }
                return index
            }
            candidates = RedeemCodeScan.candidates(from: last + 1, count: RedeemCodeScan.choiceBatchSize)
        }
        throw OneTimeAccountError.invalidIndex
    }

    /// Scans the account's one-time accounts from index 0 for codes with unspent notes.
    ///
    /// The scan reads batches of ``RedeemCodeScan/discoveryBatchSize`` indices, deriving only their addresses, until a batch has none used, so gaps
    /// that abandoned preparations leave are skipped. The used one-time accounts then sync from the start, concurrently, while their lamports are read.
    /// - Parameters:
    ///   - keys: The account's kept keys.
    ///   - client: The network's client.
    /// - Returns: A discovered ledger with the codes that hold unspent notes and the index above the highest used one.
    /// - Throws: A derivation, sync, or provider error.
    private func discoveredLedger(from keys: PrivateBalanceKeyRecord, client: Client) async throws -> RedeemCodeLedger {
        var fundings: [RedeemCodeScan.Funding] = []
        var candidates = RedeemCodeScan.candidates(from: 0, count: RedeemCodeScan.discoveryBatchSize)
        while let last = candidates.last {
            let found = try await RedeemCodeScan.fundings(of: candidates, from: keys, using: client)
            guard !found.isEmpty else { break }
            fundings += found
            candidates = RedeemCodeScan.candidates(from: last + 1, count: RedeemCodeScan.discoveryBatchSize)
        }
        async let unspent = RedeemCodeScan.unspentLamports(of: fundings, from: keys, using: client)
        async let balances = Self.lamports(of: fundings.map(\.address), using: client)
        let (notes, reserves) = try await (unspent, balances)
        let records = zip(fundings, reserves).compactMap { funding, reserve in
            notes[funding.index].map {
                RedeemCodeRecord(index: funding.index, amount: $0, reserve: reserve, created: .now,
                                 fundingSignature: funding.signature)
            }
        }
        return RedeemCodeLedger(records: records, nextIndex: fundings.last.map { $0.index + 1 } ?? 0,
                                isDiscovered: true)
    }

    /// Reads an account's kept keys.
    /// - Parameters:
    ///   - account: The account.
    ///   - generation: The ``generation`` when the operation started.
    /// - Returns: The account's keys, or `nil` without them.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`, ``KeychainItemError/unreadable`` if
    ///   the item is unreadable again after its deletion this launch, or a storage error.
    private func keyRecord(of account: Account, from generation: Int) async throws -> PrivateBalanceKeyRecord? {
        try await rebuilding(keys, .keys, from: generation) { try await $0.load() }?[account.address.value]
    }

    /// Reads accounts' finalized lamports with one `getMultipleAccounts` read per 100 addresses, run concurrently.
    /// - Parameters:
    ///   - addresses: The accounts.
    ///   - client: The network's client.
    /// - Returns: Each account's lamports, zero for a missing account, in the addresses' order.
    /// - Throws: ``PreparerError/inconsistentResponse`` if the provider returns another number of accounts, or a
    ///   provider error.
    @concurrent
    private static func lamports(of addresses: [Address], using client: Client) async throws -> [UInt64] {
        let groups = stride(from: 0, to: addresses.count, by: 100).map {
            Array(addresses[$0..<min($0 + 100, addresses.count)])
        }
        return try await withThrowingTaskGroup(of: (Int, [UInt64]).self) { group in
            for (position, batch) in groups.enumerated() {
                group.addTask {
                    let response = try await client.send(GetMultipleAccounts(addresses: batch.map(\.value)))
                    guard response.value.count == batch.count else { throw PreparerError.inconsistentResponse }
                    return (position, response.value.map { $0?.lamports ?? 0 })
                }
            }
            var reads = [[UInt64]](repeating: [], count: groups.count)
            for try await (position, lamports) in group { reads[position] = lamports }
            return reads.flatMap(\.self)
        }
    }
}
