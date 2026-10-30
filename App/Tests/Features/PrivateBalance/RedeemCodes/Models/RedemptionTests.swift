import CryptoKit
import Foundation
import Privacy
import Testing
import Transactions
import Wallet
@testable import widgets

struct RedemptionTests {
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

    @Test
    func `A network fee above the available lamports is underfunded`() throws {
        let redemption = try Self.redemption(noteLamports: 2_000_000, available: 10_000)

        #expect(throws: PrivateBalanceError.codeUnderfunded) { try redemption.charging(10_001) }
    }

    @Test
    func `A new fee replaces the old one`() throws {
        let redemption = try Self.redemption(noteLamports: 1, available: 10_000)

        #expect(try redemption.charging(9_000).charging(2_000).depositLamports == 8_000)
    }

    @Test
    func `Totals above a 64-bit integer are rejected`() {
        #expect(throws: Transactions.ValidationError.invalidAmount) {
            try Self.redemption(noteLamports: .max, available: 1)
        }
    }

    @Test
    func `A reserve pays the rent, two signatures, and one tree fee`() throws {
        #expect(try Redemption.reserve(rent: 1_330_960, treeFee: 108) == 1_341_068)
    }

    @Test(arguments: [(.max, 0), (.max - 10_000, 1)] as [(UInt64, UInt64)])
    func `Reserves above a 64-bit integer are rejected`(rent: UInt64, treeFee: UInt64) {
        #expect(throws: Transactions.ValidationError.invalidAmount) { try Redemption.reserve(rent: rent, treeFee: treeFee) }
    }

    private static func redemption(noteLamports: UInt64, available: UInt64) throws -> Redemption {
        let oneTime = try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 7, count: 32)))
        let source = try Address(oneTime.address)
        let recipient = try oneTime.shieldedAccount.recipient
        return try Redemption(instructions: [try MemoProgram.memo("sweep", signers: [source])], noteLamports: noteLamports,
                              availableLamports: available, source: source, recipient: recipient, treeID: 1,
                              takenBackIndex: nil)
    }
}
