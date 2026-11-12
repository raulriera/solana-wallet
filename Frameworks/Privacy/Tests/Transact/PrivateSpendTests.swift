@testable import Privacy
import Testing
import Transactions

struct PrivateSpendTests {
    @Test(arguments: PrivateToken.allCases)
    func `Token withdrawals pay into and open the owner's associated token account`(token: PrivateToken) throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)
        let payer = try Address(TransferVectors.senderSigningAddress)
        let destination = PrivateSpend.Destination.tokenWithdrawal(token, owner: owner)

        let tokenAccount = try TokenProgram.token.associatedAccount(owner: owner, mint: token.mint)
        #expect(try destination.tokenAccount == tokenAccount)
        #expect(try destination.parts(moving: 1).withdrawal?.recipient == tokenAccount)
        #expect(try destination.openingTokenAccount(paidBy: payer)
            == AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint, program: .token, payer: payer))
    }

    @Test
    func `Other destinations have no token account to open`() throws {
        let destination = PrivateSpend.Destination.withdrawal(try Address(TransferVectors.recipientSigningAddress))

        #expect(try destination.tokenAccount == nil)
        #expect(try destination.openingTokenAccount(paidBy: Address(TransferVectors.senderSigningAddress)) == nil)
    }
}
