@testable import Privacy
import Testing
import Transactions

struct PrivateSpendTests {
    @Test
    func `Spend diagnostics omit the values`() throws {
        let spend = PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), amount: 4, receivedAmount: 6,
            treeIDs: [0], nullifiers: [TransferVectors.blinding(0x11)], asset: .sol
        )
        var dumped = ""
        dump(spend, to: &dumped)

        #expect(String(describing: spend) == "PrivateSpend")
        #expect(String(reflecting: spend) == "PrivateSpend")
        #expect(dumped == "- PrivateSpend\n")
    }

    @Test(arguments: PrivateToken.allCases)
    func `Token withdrawals pay into and open the owner's associated token account`(token: PrivateToken) throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)
        let payer = try Address(TransferVectors.senderSigningAddress)
        let destination = PrivateSpend.Destination.tokenWithdrawal(token, owner: owner)

        let tokenAccount = try TokenProgram.token.associatedAccount(owner: owner, mint: token.mint)
        #expect(try destination.tokenAccount == tokenAccount)
        #expect(try destination.parts(moving: 1).withdrawal?.recipient == tokenAccount)
        #expect(try destination.openingTokenAccount(paidBy: payer)
            == TokenProgram.token.createAssociatedAccount(owner: owner, mint: token.mint, payer: payer))
    }

    @Test
    func `Other destinations have no token account to open`() throws {
        let destination = PrivateSpend.Destination.withdrawal(try Address(TransferVectors.recipientSigningAddress))

        #expect(try destination.tokenAccount == nil)
        #expect(try destination.openingTokenAccount(paidBy: Address(TransferVectors.senderSigningAddress)) == nil)
    }
}
