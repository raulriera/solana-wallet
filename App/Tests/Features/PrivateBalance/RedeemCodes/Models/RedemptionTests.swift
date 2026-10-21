import CryptoKit
import Foundation
import Privacy
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies the arithmetic that sweeps a code's one-time account to exactly zero lamports: the lamports left after the
/// registration and tree fees, the network fee charged to the trailing deposit, and a new code's reserve.
struct RedemptionTests {
    /// For every cost mix, the deposit is exactly the one-time account's lamports less the costs, so the account ends at
    /// zero lamports.
    /// - Parameters:
    ///   - balance: The one-time account's lamports.
    ///   - registrationCost: The registration's cost.
    ///   - treeFee: The tree's fee per nullifier.
    ///   - nullifierCount: The spend's input slots.
    ///   - networkFee: The network fee and tips.
    ///   - deposit: The expected deposit.
    @Test(arguments: [
        (UInt64(1_341_068), UInt64(0), UInt64(108), 1, UInt64(5_000), UInt64(1_335_960)),
        (1_341_068, 1_330_960, 108, 1, 10_000, 0),
        (2_000_000, 1_330_960, 0, 2, 10_000, 659_040),
        (UInt64.max, UInt64.max - 1_000, 100, 4, 600, 0),
    ])
    func `The costs and the deposit add up to the one-time account's lamports`(
        balance: UInt64, registrationCost: UInt64, treeFee: UInt64, nullifierCount: Int, networkFee: UInt64, deposit: UInt64
    ) throws {
        let available = try Redemption.availableLamports(of: balance, registrationCost: registrationCost,
                                                         treeFee: treeFee, nullifierCount: nullifierCount)

        #expect(try Self.redemption(noteLamports: 0, available: available).charging(networkFee).depositLamports == deposit)
    }

    /// The registration and tree fees, or the network fee, can't exceed the one-time account's lamports, even when their
    /// product or sum overflows.
    /// - Parameters:
    ///   - balance: The one-time account's lamports.
    ///   - registrationCost: The registration's cost.
    ///   - treeFee: The tree's fee per nullifier.
    ///   - nullifierCount: The spend's input slots.
    @Test(arguments: [
        (UInt64(1_000), UInt64(900), UInt64(101), 1),
        (1_000, 0, UInt64.max / 2 + 1, 2),
        (UInt64.max, UInt64.max, 1, 1),
    ])
    func `Costs above the lamports are underfunded`(balance: UInt64, registrationCost: UInt64, treeFee: UInt64,
                                                    nullifierCount: Int) {
        #expect(throws: PrivateBalanceError.codeUnderfunded) {
            try Redemption.availableLamports(of: balance, registrationCost: registrationCost, treeFee: treeFee,
                                             nullifierCount: nullifierCount)
        }
    }

    /// The network fee comes out of the deposit, and the whole of the available lamports leaves no deposit.
    @Test
    func `The network fee comes out of the deposit`() throws {
        let redemption = try Self.redemption(noteLamports: 2_000_000, available: 10_000)
        let memo = try #require(redemption.instructions.first)

        let charged = try redemption.charging(4_000)
        let drained = try redemption.charging(10_000)

        #expect(charged.depositLamports == 6_000)
        #expect(charged.lamports == 2_006_000)
        #expect(try charged.transactionInstructions == [
            memo, try ShieldedPool.deposit(lamports: 6_000, from: redemption.source, to: redemption.recipient, treeID: 1),
        ])
        #expect(drained.lamports == 2_000_000)
        #expect(try drained.transactionInstructions == [memo])
    }

    /// A network fee above the available lamports is underfunded.
    @Test
    func `A network fee above the available lamports is underfunded`() throws {
        let redemption = try Self.redemption(noteLamports: 2_000_000, available: 10_000)

        #expect(throws: PrivateBalanceError.codeUnderfunded) { try redemption.charging(10_001) }
    }

    /// Charging a fee replaces the fee charged before.
    @Test
    func `A new fee replaces the old one`() throws {
        let redemption = try Self.redemption(noteLamports: 1, available: 10_000)

        #expect(try redemption.charging(9_000).charging(2_000).depositLamports == 8_000)
    }

    /// Notes and available lamports that together exceed a 64-bit integer are rejected.
    @Test
    func `Totals above a 64-bit integer are rejected`() {
        #expect(throws: Transactions.ValidationError.invalidAmount) {
            try Self.redemption(noteLamports: .max, available: 1)
        }
    }

    /// A new code's reserve pays a registration record's rent, two signatures, and one nullifier's tree fee.
    @Test
    func `A reserve pays the rent, two signatures, and one tree fee`() throws {
        #expect(try Redemption.reserve(rent: 1_330_960, treeFee: 108) == 1_341_068)
    }

    /// A reserve above a 64-bit integer is rejected.
    /// - Parameters:
    ///   - rent: The registration record's rent.
    ///   - treeFee: The tree's fee per nullifier.
    @Test(arguments: [(.max, 0), (.max - 10_000, 1)] as [(UInt64, UInt64)])
    func `Reserves above a 64-bit integer are rejected`(rent: UInt64, treeFee: UInt64) {
        #expect(throws: Transactions.ValidationError.invalidAmount) { try Redemption.reserve(rent: rent, treeFee: treeFee) }
    }

    /// Creates a redemption of a fixture one-time account into its own shielded address, with a memo before its deposit.
    /// - Parameters:
    ///   - noteLamports: The notes' lamports.
    ///   - available: The lamports left for the network fee and the deposit.
    /// - Returns: The redemption before its network fee.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for totals above a 64-bit integer, or a fixture error.
    private static func redemption(noteLamports: UInt64, available: UInt64) throws -> Redemption {
        let oneTime = try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 7, count: 32)))
        let source = try Address(oneTime.address)
        let recipient = try oneTime.shieldedAccount.recipient
        return try Redemption(instructions: [try MemoProgram.memo("sweep", signers: [source])], noteLamports: noteLamports,
                              availableLamports: available, source: source, recipient: recipient, treeID: 1,
                              takenBackIndex: nil)
    }
}
