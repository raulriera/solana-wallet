import Foundation
import Testing
import Transactions

/// Verifies V1 signature placement and failure boundaries through the public assembler.
struct TransactionBuilderTests {
    /// Verifies the complete envelope against an independently signed Solana SDK fixture.
    @Test("signed SOL transfers match Solana SDK V1 transaction bytes")
    func signedTransfersMatchSolanaTransactionBytes() throws {
        let transfer = try Transfer(sender: Address(SignedTransferFixture.sender),
                                    recipient: Address(MessageFixture.recipient), lamports: 1_000_000_000)
        let configuration = try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                                               loadedAccountsDataSizeLimit: 65_536)
        let message = try MessageBuilder().message(for: transfer, recentBlockhash: MessageFixture.zeroBlockhash,
                                                   configuration: configuration)
        let builder: any TransactionBuilding = TransactionBuilder()

        let transaction = try builder.transaction(
            for: message, signature: SignedTransferFixture.bytes(SignedTransferFixture.signature)
        )

        #expect(transaction == (try SignedTransferFixture.bytes(SignedTransferFixture.transaction)))
    }

    /// Verifies a signature can't be reused after changing the transfer amount.
    @Test("changing the lamport amount invalidates the transaction signature")
    func changedAmountInvalidatesSignature() throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        message[message.count - 8] ^= 1
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.signature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(for: message, signature: signature)
        }
    }

    /// Verifies the public key used for verification comes from the encoded fee payer.
    @Test("a signature from another sender is rejected")
    func signatureFromAnotherSenderIsRejected() throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.otherSignature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(for: message, signature: signature)
        }
    }

    /// Verifies the identity key cannot forge approval of either transfer amount.
    ///
    /// - Parameter changesAmount: Whether to reuse the forgery after changing the lamports.
    @Test("identity signers cannot authorize transfers", arguments: [false, true])
    func identitySignersCannotAuthorizeTransfers(changesAmount: Bool) throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let identity = Data([1] + Array(repeating: 0, count: 31))
        message.replaceSubrange(42..<74, with: identity)
        if changesAmount { message[message.count - 8] ^= 1 }
        let signature = identity + Data(repeating: 0, count: 32)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(for: message, signature: signature)
        }
    }

    /// Verifies a strong signer does not make a small-order signature point acceptable.
    @Test("signatures with an identity nonce point are rejected")
    func identityNoncePointsAreRejected() throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.identityNonceSignature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(for: message, signature: signature)
        }
    }

    /// Verifies missing, truncated, and oversized signature fields fail closed.
    ///
    /// - Parameter count: An invalid signature length in bytes.
    @Test("transaction assembly rejects incomplete signature fields", arguments: [0, 63, 65])
    func invalidSignatureLengthsAreRejected(_ count: Int) throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(for: message, signature: Data(repeating: 0, count: count))
        }
    }

    /// Verifies inputs outside this milestone's single-signer V1 contract are rejected.
    ///
    /// - Parameter input: An empty, unsupported, truncated, or oversized message.
    @Test("transaction assembly rejects unsupported message headers and sizes", arguments: [
        "empty", "legacy", "v0", "multiple signers", "readonly signer", "truncated accounts", "oversized"
    ])
    func unsupportedMessagesAreRejected(_ input: String) throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        switch input {
        case "empty": message = Data()
        case "legacy": message[0] = 1
        case "v0": message[0] = 0x80
        case "multiple signers": message[1] = 2
        case "readonly signer": message[2] = 1
        case "truncated accounts": message = Data(message.prefix(73))
        default: message = Data(message + Data(repeating: 0, count: 4_096))
        }

        #expect(throws: ValidationError.invalidMessage) {
            try TransactionBuilder().transaction(for: message, signature: Data(repeating: 0, count: 64))
        }
    }
}
