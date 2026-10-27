import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies redeem codes on devnet end to end: real private balances over in-memory storage, the selected provider's
/// real client, and the shared transaction pipeline with your devnet test wallet.
///
/// One ordered flow runs from account 0 to account 1, and the redeemed funds stay with account 1. Both accounts must
/// already be registered, as ``PrivateTransferLiveTests`` leaves them:
///
/// 1. Account 0 deposits 10,000,000 lamports into its own private balance only when that balance is below 6,000,000.
/// 2. Account 0 creates a 2,000,000-lamport code, and account 1 redeems it; the code's one-time account ends at zero
///    lamports, and account 1's private balance gains the note and what's left of the code's reserve.
/// 3. Account 0 creates a 1,000,000-lamport code and takes it back; its one-time account ends at zero lamports.
/// 4. Redeeming the taken-back code fails as already redeemed, without a transaction.
///
/// Costs: each code moves its amount and a reserve of a registration record's rent, 1,330,960 lamports, plus 10,000
/// lamports and one tree fee out of account 0's private balance. Account 1 keeps 2,000,000 lamports and the first
/// reserve less 5,000 lamports and a tree fee; account 0 gets the second code back less 5,000 lamports and a tree fee.
/// Account 0 pays about 2 × 5,000 lamports of public fees and the codes' tree fees, and a 10,000,000-lamport deposit
/// only when its private balance is low. A missing seed or key, or an unfunded account 0, stops setup.
@Suite(.serialized, .tags(.network), .timeLimit(.minutes(10)))
struct RedeemCodeLiveTests {
    /// The lamports that a run's deposit moves into account 0's private balance.
    private static let depositLamports: UInt64 = 10_000_000

    /// The private balance below which a run deposits first: enough for both codes and their reserves.
    private static let minimumPrivateLamports: UInt64 = 6_000_000

    /// The lamports of the code that account 1 redeems.
    private static let redeemedLamports: UInt64 = 2_000_000

    /// The lamports of the code that account 0 takes back.
    private static let takenBackLamports: UInt64 = 1_000_000

    /// The public lamports that account 0 keeps for a run's fees.
    private static let feeLamports: UInt64 = 100_000

    /// Creates a code that account 1 redeems and a code that account 0 takes back, checking that each one-time account
    /// ends at zero lamports and that the taken-back code can't be redeemed.
    /// - Throws: A configuration, provider, proof, signing, or test prerequisite error.
    @Test
    func `Codes are redeemed and taken back to exactly zero lamports`() async throws {
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
        try await balances.enable(sender, on: .devnet)
        try await balances.enable(recipient, on: .devnet)
        try #require(try await balances.refresh(recipient, on: .devnet) != .unregistered,
                     "Run PrivateTransferLiveTests first so that account 1 is registered.")
        var log: [String] = []

        // 1. Account 0 deposits into its own private balance when it's low.
        if try await Self.settledBalance(of: sender, in: balances) < Self.minimumPrivateLamports {
            let deposit = try await balances.prepare(.deposit(Self.depositLamports), from: sender, on: .devnet)
            try #require(!deposit.registers, "Run PrivateTransferLiveTests first so that account 0 is registered.")
            try await Self.requireFunds(Self.depositLamports + Self.feeLamports, in: sender, using: rpc)
            let (confirmation, _) = try await Self.run(deposit, through: coordinator)
            _ = try await balances.complete(deposit, with: confirmation)
            log.append("deposit \(confirmation.submission.signature)")
        }

        // 2. Account 0 creates a code, and account 1 redeems it.
        let redeemed = try await Self.createCode(of: Self.redeemedLamports, from: sender, in: balances, through: coordinator,
                                                 log: &log)
        let recipientLamports = try await Self.settledBalance(of: recipient, in: balances)
        let redemption = try await Self.preparedWhenIndexed(.redeem(redeemed.code), into: recipient, in: balances)
        let (redeemedConfirmation, charged) = try await Self.run(redemption, through: coordinator)
        let swept = try #require(Self.redemption(in: charged))
        #expect(try await balances.complete(charged, with: redeemedConfirmation) == .balance(available: recipientLamports, pending: swept.lamports))
        let redeemedFinal = try await Self.lamports(of: redeemed.code, after: redeemedConfirmation, using: rpc)
        log.append("redeem \(redeemedConfirmation.submission.signature) one-time final lamports \(redeemedFinal)")
        #expect(redeemedFinal == 0)
        #expect(swept.noteLamports == Self.redeemedLamports)
        #expect(swept.networkFee == Redemption.signatureFee)

        // 3. Account 0 creates a code and takes it back.
        let takenBack = try await Self.createCode(of: Self.takenBackLamports, from: sender, in: balances,
                                                  through: coordinator, log: &log)
        let takeBack = try await Self.preparedWhenIndexed(.takeBack(index: takenBack.record.index), into: sender,
                                                          in: balances)
        let (takenBackConfirmation, chargedTakeBack) = try await Self.run(takeBack, through: coordinator)
        _ = try await balances.complete(chargedTakeBack, with: takenBackConfirmation)
        let takenBackFinal = try await Self.lamports(of: takenBack.code, after: takenBackConfirmation, using: rpc)
        log.append("take-back \(takenBackConfirmation.submission.signature) one-time final lamports \(takenBackFinal)")
        #expect(takenBackFinal == 0)
        #expect(try await !balances.outstandingCodes(of: sender, on: .devnet).map(\.record.index)
            .contains(takenBack.record.index))

        // 4. The taken-back code can't be redeemed again.
        await #expect(throws: widgets.PrivateBalanceError.codeRedeemed) {
            try await balances.prepare(.redeem(takenBack.code), from: recipient, on: .devnet)
        }
        Attachment.record(log.joined(separator: "\n"), named: "Redeem code signatures")
    }

    /// Creates a code from account 0's settled private balance and lists it.
    /// - Parameters:
    ///   - lamports: The code's private amount.
    ///   - sender: Account 0.
    ///   - balances: The private balances.
    ///   - coordinator: The devnet transaction pipeline.
    ///   - log: The run's signatures, which gains the code's funding.
    /// - Returns: The outstanding code.
    /// - Throws: A provider, proof, signing, or test prerequisite error.
    private static func createCode(of lamports: UInt64, from sender: widgets.Account, in balances: PrivateBalances,
                                   through coordinator: TransactionCoordinator,
                                   log: inout [String]) async throws -> OutstandingRedeemCode {
        let prepared = try await balances.prepare(.createCode(lamports), from: sender, on: .devnet)
        guard case .createCode(_, let index, _) = prepared.effect else {
            return try #require(nil as OutstandingRedeemCode?, "Expected a code's creation.")
        }
        let (confirmation, _) = try await run(prepared, through: coordinator)
        _ = try await balances.complete(prepared, with: confirmation)
        log.append("create \(lamports) at index \(index) \(confirmation.submission.signature)")
        let outstanding = try await balances.outstandingCodes(of: sender, on: .devnet)
        return try #require(outstanding.first { $0.record.index == index }, "The new code isn't outstanding.")
    }

    /// Prepares a redeem or take-back once the indexer reports the code's note.
    /// - Parameters:
    ///   - request: The redeem or take-back.
    ///   - account: The receiving account.
    ///   - balances: The private balances.
    /// - Returns: The prepared sweep.
    /// - Throws: A provider or proof error, or a test prerequisite error if the note isn't indexed within a minute.
    private static func preparedWhenIndexed(_ request: PrivateTransactionRequest, into account: widgets.Account,
                                            in balances: PrivateBalances) async throws -> PreparedPrivateTransaction {
        for _ in 0..<30 {
            do {
                return try await balances.prepare(request, from: account, on: .devnet)
            } catch let error as widgets.PrivateBalanceError where error == .codeNotReady {
                try await Task.sleep(for: .seconds(2))
            }
        }
        return try #require(nil as PreparedPrivateTransaction?, "The indexer didn't report the code within a minute.")
    }

    /// Simulates, signs, sends, and confirms a prepared transaction through the shared pipeline, charging a sweep's
    /// network fee first.
    /// - Parameters:
    ///   - transaction: The prepared transaction.
    ///   - coordinator: The devnet transaction pipeline.
    /// - Returns: The settled outcome, which must have succeeded, and the transaction to complete.
    /// - Throws: A simulation failure as a test prerequisite error, or a preparation, signing, or delivery error.
    private static func run(_ transaction: PreparedPrivateTransaction, through coordinator: TransactionCoordinator)
        async throws -> (widgets.Confirmation, PreparedPrivateTransaction) {
        let (simulation, charged) = try await coordinator.simulate(transaction)
        try #require(simulation.diagnostics.value.error == nil, "Simulation failed: \(simulation.diagnostics.value.logs ?? [])")
        let confirmation = try await coordinator.confirm(coordinator.submit(simulation))
        try #require(confirmation.outcome == .succeeded)
        return (confirmation, charged)
    }

    /// Reads a code's one-time account at or after a transaction's execution slot.
    /// - Parameters:
    ///   - code: The code.
    ///   - confirmation: The transaction that swept it.
    ///   - rpc: The devnet client.
    /// - Returns: The one-time account's finalized lamports, zero if it no longer exists.
    /// - Throws: A derivation or provider error.
    private static func lamports(of code: RedeemCode, after confirmation: widgets.Confirmation,
                                 using rpc: HeliusRPC) async throws -> UInt64 {
        let address = try OneTimeAccount(secret: code.secret).address
        let slot = try await confirmation.executionSlot(through: rpc)
        let response = try await rpc.send(GetMultipleAccounts(addresses: [address], minContextSlot: slot))
        return (response.value.first ?? nil)?.lamports ?? 0
    }

    /// Reads a sweep's redemption.
    /// - Parameter transaction: A prepared transaction.
    /// - Returns: Its redemption, or `nil` for another transaction.
    private static func redemption(in transaction: PreparedPrivateTransaction) -> Redemption? {
        guard case .redeem(let redemption) = transaction.effect else { return nil }
        return redemption
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

    /// Refreshes an account's private balance until the indexer reports every recorded transaction, so that all of it
    /// can be spent.
    /// - Parameters:
    ///   - account: The account.
    ///   - balances: The private balances.
    /// - Returns: The settled balance.
    /// - Throws: A provider error, or a test prerequisite error if the indexer doesn't catch up within a minute.
    private static func settledBalance(of account: widgets.Account, in balances: PrivateBalances) async throws -> UInt64 {
        for _ in 0..<30 {
            if case .balance(let available, pending: 0) = try await balances.refresh(account, on: .devnet) {
                return available
            }
            try await Task.sleep(for: .seconds(2))
        }
        return try #require(nil as UInt64?, "The indexer didn't report the recorded transactions within a minute.")
    }
}
