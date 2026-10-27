import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies private deposits, sends, and withdrawals on devnet end to end: real private balances over in-memory storage,
/// the selected provider's real client, and the shared transaction pipeline with your devnet test wallet.
///
/// One ordered flow runs from account 0 to account 1, and the funds stay with account 1:
///
/// 1. Account 1 registers its private-balance keys if it hasn't, signing as the owner while account 0 pays.
/// 2. Account 0 deposits 10,000,000 lamports into its own private balance only when that balance is below 4,000,000;
///    its first deposit also registers its keys in the same transaction.
/// 3. Account 0 sends 2,000,000 lamports privately to account 1, the first live proof.
/// 4. Account 0 withdraws 2,000,000 lamports from its private balance to account 1's public address.
///
/// Costs: the two registrations are one-time and permanent, 1,330,960 lamports of rent each. Each run moves about
/// 4,000,000 lamports to account 1, plus about 3 × 5,000 lamports of fees, and a 10,000,000-lamport deposit only when
/// account 0's private balance is low. A missing seed or key, or an unfunded account 0, stops setup.
@Suite(.serialized, .tags(.network), .timeLimit(.minutes(10)))
struct PrivateTransferLiveTests {
    /// The lamports that a run's deposit moves into account 0's private balance.
    private static let depositLamports: UInt64 = 10_000_000

    /// The private balance below which a run deposits first: enough for the send and the withdrawal.
    private static let minimumPrivateLamports: UInt64 = 4_000_000

    /// The lamports of the private send and of the withdrawal.
    private static let transferLamports: UInt64 = 2_000_000

    /// The rent of one user-registry record.
    private static let registrationLamports: UInt64 = 1_330_960

    /// The public lamports that account 0 keeps for a run's fees.
    private static let feeLamports: UInt64 = 100_000

    /// Registers account 1, deposits when needed, sends privately, and withdraws, checking each recorded balance and
    /// account 1's public balance at the withdrawal's slot.
    /// - Throws: A configuration, provider, proof, signing, or test prerequisite error.
    @Test
    func `Private deposits, sends, and withdrawals move SOL between the test accounts`() async throws {
        let wallets = try await DevnetWallets.configured()
        let apiKey = try LiveClients.heliusAPIKey()
        let rpc = HeliusRPC(apiKey: apiKey, network: .devnet)
        let sender = wallets.sender
        let recipient = wallets.recipient
        try await Self.requireFunds(Self.feeLamports, in: sender, using: rpc)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery),
                                                     strategy: .none)
        let notes = StoredValue<PrivateBalances.Notes>()
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let providers = await ProviderStore.inMemory(settings, key: StoredValue(apiKey))
        let balances = PrivateBalances(
            recovery: SecurityRecoveryStore(records: [sender.recoveryID: wallets.recovery]), wallet: Wallet(),
            keys: StoredValue(), notes: notes, codes: StoredValue()
        ) { network in
            ProviderClient(network: network, providers: providers)
        }

        // 1. Account 1 registers, signing as the owner, while account 0 pays its rent.
        let recipientKeys = try await Self.keys(of: recipient, from: wallets)
        switch try await recipientKeys.registration(using: rpc) {
        case .unregistered:
            try await Self.requireFunds(Self.registrationLamports + Self.feeLamports, in: sender, using: rpc)
            let confirmation = try await Self.run([try recipientKeys.register(paidBy: sender.address)],
                                                  signedBy: [sender, recipient], through: coordinator)
            try #require(confirmation.outcome == .succeeded)
            try await Self.awaitRegistration(of: recipientKeys, using: rpc)
        case .registeredWithOtherKeys:
            Issue.record("Account 1 registered other private-balance keys.")
            return
        case .registered:
            break
        }
        try await balances.enable(sender, on: .devnet)
        try await balances.enable(recipient, on: .devnet)

        // 2. Account 0 deposits into its own private balance when it's low.
        var privateLamports = try await Self.settledBalance(of: sender, in: balances)
        if privateLamports < Self.minimumPrivateLamports {
            let deposit = try await balances.prepare(.deposit(Self.depositLamports), from: sender, on: .devnet)
            let rent = deposit.registers ? Self.registrationLamports : 0
            try await Self.requireFunds(Self.depositLamports + rent + Self.feeLamports, in: sender, using: rpc)
            let confirmation = try await Self.run(deposit.instructions, signedBy: [sender], through: coordinator)
            try #require(confirmation.outcome == .succeeded)
            #expect(try await balances.complete(deposit, with: confirmation) == .balance(available: privateLamports, pending: Self.depositLamports))
            privateLamports = try await Self.settledBalance(of: sender, in: balances)
        }

        // 3. Account 0 sends privately to account 1.
        let send = try await balances.prepare(.send(Self.transferLamports, to: recipient.address), from: sender, on: .devnet)
        let sent = try await Self.run(send.instructions, signedBy: [sender], through: coordinator)
        try #require(sent.outcome == .succeeded)
        let sentChange = Self.change(of: send)
        #expect(try await balances.complete(send, with: sent)
            == .balance(available: privateLamports - Self.transferLamports - sentChange, pending: sentChange))
        privateLamports = try await Self.settledBalance(of: sender, in: balances)

        // 4. Account 0 withdraws to account 1's public address.
        let before = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value]))
        let publicLamports = (before.value.first ?? nil)?.lamports ?? 0
        let withdrawal = try await balances.prepare(.withdraw(Self.transferLamports, to: recipient.address), from: sender,
                                                    on: .devnet)
        let withdrawn = try await Self.run(withdrawal.instructions, signedBy: [sender], through: coordinator)
        try #require(withdrawn.outcome == .succeeded)
        let withdrawnChange = Self.change(of: withdrawal)
        #expect(try await balances.complete(withdrawal, with: withdrawn)
            == .balance(available: privateLamports - Self.transferLamports - withdrawnChange, pending: withdrawnChange))
        let slot = try await withdrawn.executionSlot(through: rpc)
        let after = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value], minContextSlot: slot))
        #expect((after.value.first ?? nil)?.lamports == publicLamports + Self.transferLamports)
    }

    /// Stops setup unless account 0 holds enough public lamports for the next step.
    /// - Parameters:
    ///   - lamports: The lamports that the step needs, fees included.
    ///   - sender: Account 0.
    ///   - rpc: The devnet client.
    /// - Throws: A provider error, or a test prerequisite error that names the address to fund.
    private static func requireFunds(_ lamports: UInt64, in sender: widgets.Account, using rpc: HeliusRPC) async throws {
        let funds = try await rpc.send(GetMultipleAccounts(addresses: [sender.address.value]))
        try #require((funds.value.first ?? nil)?.lamports ?? 0 >= lamports,
                     "Account 0 must hold \(lamports) lamports of devnet SOL; fund \(sender.address.value)")
    }

    /// Waits until the finalized registry, which recipient lookups read, holds an account's record.
    /// - Parameters:
    ///   - account: The account's shielded keys.
    ///   - rpc: The devnet client.
    /// - Throws: A provider error, or a test prerequisite error if the record isn't finalized within a minute.
    private static func awaitRegistration(of account: ShieldedAccount, using rpc: HeliusRPC) async throws {
        for _ in 0..<30 {
            if try await account.registration(using: rpc) == .registered { return }
            try await Task.sleep(for: .seconds(2))
        }
        try #require(try await account.registration(using: rpc) == .registered, "The registration wasn't finalized within a minute.")
    }

    /// Derives an account's private-balance keys from the configured recovery.
    /// - Parameters:
    ///   - account: The account.
    ///   - wallets: The configured devnet wallet.
    /// - Returns: The account's shielded keys.
    /// - Throws: A derivation error.
    private static func keys(of account: widgets.Account, from wallets: DevnetWallets) async throws -> ShieldedAccount {
        try PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: wallets.recovery.phrase, expectedAddress: account.address.value, passphrase: wallets.recovery.passphrase,
            path: account.path
        )).shieldedAccount(for: account.address)
    }

    /// Simulates, signs, sends, and confirms one transaction through the shared pipeline.
    /// - Parameters:
    ///   - instructions: The transaction's ordered instructions.
    ///   - signers: The signing accounts; the first pays the fee.
    ///   - coordinator: The devnet transaction pipeline.
    /// - Returns: The transaction's settled outcome.
    /// - Throws: A simulation failure as a test prerequisite error, or a preparation, signing, or delivery error.
    private static func run(_ instructions: [Instruction], signedBy signers: [widgets.Account],
                            through coordinator: TransactionCoordinator) async throws -> widgets.Confirmation {
        let simulation = try await coordinator.simulate(instructions, using: signers)
        try #require(simulation.diagnostics.value.error == nil, "Simulation failed: \(simulation.diagnostics.value.logs ?? [])")
        return try await coordinator.confirm(coordinator.submit(simulation))
    }

    /// Reads the change that a spend returns to the private balance, which stays pending until the indexer reports it.
    /// - Parameter transaction: A prepared send or withdrawal.
    /// - Returns: The spend's change, or zero for another transaction.
    private static func change(of transaction: PreparedPrivateTransaction) -> UInt64 {
        guard case .spend(let spend) = transaction.effect else { return 0 }
        return spend.receivedLamports
    }

    /// Refreshes an account's private balance until the indexer reports every recorded transaction, so that all of it
    /// can be spent.
    /// - Parameters:
    ///   - account: The account.
    ///   - balances: The private balances.
    /// - Returns: The settled balance, zero before the account registers.
    /// - Throws: A provider error, or a test prerequisite error if the indexer doesn't catch up within a minute.
    private static func settledBalance(of account: widgets.Account, in balances: PrivateBalances) async throws -> UInt64 {
        for _ in 0..<30 {
            let status = try await balances.refresh(account, on: .devnet)
            if case .unregistered = status { return 0 }
            if case .balance(let available, pending: 0) = status { return available }
            try await Task.sleep(for: .seconds(2))
        }
        return try #require(nil as UInt64?, "The indexer didn't report the recorded transactions within a minute.")
    }
}
