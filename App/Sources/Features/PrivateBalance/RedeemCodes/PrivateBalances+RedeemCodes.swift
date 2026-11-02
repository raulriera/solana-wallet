import Foundation
import Privacy
import RPC
import Storage
import Transactions
import Wallet

extension PrivateBalances {
    func outstandingCodes(of account: Account, on network: Network) async throws -> [OutstandingRedeemCode] {
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
        } catch ProviderClientError.unsupportedNetwork {
            throw PrivateBalanceError.unavailable
        }
    }

    /// Builds the spend that funds a new redeem code.
    ///
    /// - Parameters:
    ///   - lamports: The code's private SOL, in lamports.
    ///   - account: The account that creates the code, signs, and pays.
    ///   - network: The network of the account's private balance.
    ///   - client: The network's client.
    /// - Returns: The prepared spend.
    /// - Throws: A ``PrivateBalanceError``, or a validation, storage, provider, proof, or cancellation error.
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
                                          from: shielded, rpc: client, prover: client)
        return PreparedPrivateTransaction(instructions: [spend.instruction], account: account, network: network,
                                          effect: .createCode(spend, index: index, reserve: reserve), registers: false,
                                          authorities: [.account(account)])
    }

    /// Builds the redeem of a code into an account's private balance.
    ///
    /// - Parameters:
    ///   - code: The code to redeem.
    ///   - account: The account that receives the code's SOL.
    ///   - network: The network of the account's private balance.
    ///   - client: The network's client.
    /// - Returns: The prepared sweep.
    /// - Throws: A ``PrivateBalanceError``, or a derivation, storage, provider, proof, or cancellation error.
    func preparedRedeem(of code: RedeemCode, into account: Account, on network: Network,
                        client: Client) async throws -> PreparedPrivateTransaction {
        async let savedKeys = keyRecord(of: account, from: generation)
        let oneTime = try OneTimeAccount(secret: code.secret)
        guard let keys = try await savedKeys else { throw PrivateBalanceError.turnedOff }
        return try await preparedRedemption(of: oneTime, into: account, keys: keys, on: network, takingBack: nil,
                                            client: client)
    }

    /// Builds the take-back of one of the account's own codes into its private balance.
    ///
    /// - Parameters:
    ///   - index: The code's index under the account's code root.
    ///   - account: The account that created the code.
    ///   - network: The network of the account's private balance.
    ///   - client: The network's client.
    /// - Returns: The prepared sweep.
    /// - Throws: A ``PrivateBalanceError``, or a derivation, storage, provider, proof, or cancellation error.
    func preparedTakeBack(at index: UInt32, into account: Account, on network: Network,
                          client: Client) async throws -> PreparedPrivateTransaction {
        guard let keys = try await keyRecord(of: account, from: generation) else { throw PrivateBalanceError.turnedOff }
        return try await preparedRedemption(of: keys.oneTimeAccount(at: index), into: account, keys: keys, on: network,
                                            takingBack: index, client: client)
    }

    /// Builds the sweep of a code's one-time account into an account's private balance.
    ///
    /// - Parameters:
    ///   - oneTime: The code's one-time account.
    ///   - account: The account that receives the code's SOL.
    ///   - keys: The receiving account's keys.
    ///   - network: The network of the account's private balance.
    ///   - index: The index of the account's own code that this takes back, or `nil` for a redeem.
    ///   - client: The network's client.
    /// - Returns: The prepared sweep.
    /// - Throws: A ``PrivateBalanceError`` for a code or account that can't be swept, or a derivation, provider,
    ///   proof, or cancellation error.
    func preparedRedemption(of oneTime: OneTimeAccount, into account: Account, keys: PrivateBalanceKeyRecord,
                            on network: Network, takingBack index: UInt32?,
                            client: Client) async throws -> PreparedPrivateTransaction {
        let shielded = try keys.shieldedAccount(for: account.address)
        let code = try oneTime.shieldedAccount
        async let codeNotes = NoteSyncState().syncedToEnd(for: code, using: client)
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
        let spend = try await state.spend(state.lamports, to: .transfer(recipient), from: code, rpc: client,
                                          prover: client)
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

    /// Records a settled transaction's change to the account's codes entry.
    ///
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
    /// - Parameters:
    ///   - id: The account's codes entry on the network.
    ///   - keys: The account's keys.
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

    /// Chooses the index of a new code and keeps it pending.
    ///
    /// - Parameters:
    ///   - id: The account's codes entry on the network.
    ///   - keys: The account's keys.
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
    /// - Parameters:
    ///   - keys: The account's keys.
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
    ///
    /// - Parameters:
    ///   - account: The account whose keys to read.
    ///   - generation: The ``generation`` when the operation started.
    /// - Returns: The account's keys, or `nil` without them.
    /// - Throws: `CancellationError` if ``removeAll()`` ran after `generation`, ``KeychainItemError/unreadable`` if
    ///   the item is still unreadable, or a storage error.
    private func keyRecord(of account: Account, from generation: Int) async throws -> PrivateBalanceKeyRecord? {
        try await rebuilding(keys, .keys, from: generation) { try await $0.load() }?[account.address.value]
    }

    /// Reads accounts' finalized lamports.
    ///
    /// - Parameters:
    ///   - addresses: The accounts' addresses.
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
