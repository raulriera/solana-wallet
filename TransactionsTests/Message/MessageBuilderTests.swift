import Foundation
import Testing
import Transactions

/// Verifies public message construction against independently generated Solana SDK bytes.
struct MessageBuilderTests {
    /// Verifies V1 headers, accounts, configuration, and transfer data as a complete message.
    ///
    /// - Parameter fixture: A public example generated with Solana Kit 8.0.0.
    @Test("SOL transfers match Solana SDK V1 message bytes", arguments: MessageFixture.transfers)
    func transfersMatchSolanaMessages(_ fixture: MessageFixture) throws {
        let builder: any MessageBuilding = MessageBuilder()
        let transfer = try Transfer(sender: Address(MessageFixture.sender),
                                    recipient: Address(MessageFixture.recipient), lamports: fixture.lamports)
        let message = try builder.message(for: transfer, recentBlockhash: fixture.blockhash,
                                          configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    /// Verifies account deduplication and lossless encoding of UInt64 amounts and fees.
    @Test("self transfers reuse the signer and preserve maximum lamport values")
    func selfTransfersReuseSignerAndPreserveMaximumLamports() throws {
        let fixture = MessageFixture.selfTransfer
        let sender = try Address(MessageFixture.sender)
        let transfer = try Transfer(sender: sender, recipient: sender, lamports: fixture.lamports)
        let message = try MessageBuilder().message(for: transfer, recentBlockhash: fixture.blockhash,
                                                   configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    /// Verifies malformed blockhashes fail before message bytes are returned.
    @Test("message construction rejects an invalid recent blockhash")
    func messageConstructionRejectsInvalidBlockhash() throws {
        let transfer = try Transfer(sender: Address(MessageFixture.sender),
                                    recipient: Address(MessageFixture.recipient), lamports: 1)
        let configuration = try MessageFixture.transfers[0].configuration()

        #expect(throws: ValidationError.invalidBlockhash) {
            try MessageBuilder().message(for: transfer, recentBlockhash: "invalid", configuration: configuration)
        }
    }
}
