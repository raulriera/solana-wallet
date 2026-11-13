import Foundation
import Testing
import Transactions

struct TransactionBuilderTests {
    @Test
    func `Unsigned simulations preserve V1 messages with one empty signature slot`() throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let builder = TransactionBuilder()

        let transaction = try builder.simulationTransaction(for: message)

        let signedFixture = try SignedTransferFixture.bytes(SignedTransferFixture.transaction)
        #expect(transaction == signedFixture.dropLast(64) + Data(repeating: 0, count: 64))
    }

    @Test
    func `Signed SOL transfers match Solana SDK V1 transaction bytes`() throws {
        let transfer = try SystemProgram.transfer(from: Address(SignedTransferFixture.sender), to: Address(MessageFixture.recipient), lamports: 1_000_000_000)
        let configuration = try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                                               loadedAccountsDataSizeLimit: 65_536)
        let message = try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: MessageFixture.zeroBlockhash,
                                                   configuration: configuration)
        let builder = TransactionBuilder()

        let transaction = try builder.transaction(
            byAdding: SignedTransferFixture.bytes(SignedTransferFixture.signature),
            for: Address(SignedTransferFixture.sender), to: builder.simulationTransaction(for: message)
        )

        #expect(transaction.serializedRepresentation == (try SignedTransferFixture.bytes(SignedTransferFixture.transaction)))
    }

    @Test
    func `Changing the lamport amount invalidates the transaction signature`() throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        message[message.count - 8] ^= 1
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.signature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(byAdding: signature,
                for: TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message)).accounts[0].address,
                to: TransactionBuilder().simulationTransaction(for: message))
        }
    }

    @Test
    func `A signature from another sender is rejected`() throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.otherSignature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(byAdding: signature,
                for: TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message)).accounts[0].address,
                to: TransactionBuilder().simulationTransaction(for: message))
        }
    }

    @Test(arguments: [false, true])
    func `Identity signers cannot authorize transfers`(changesAmount: Bool) throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let identity = Data([1] + Array(repeating: 0, count: 31))
        message.replaceSubrange(42..<74, with: identity)
        if changesAmount { message[message.count - 8] ^= 1 }
        let signature = identity + Data(repeating: 0, count: 32)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(byAdding: signature,
                for: TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message)).accounts[0].address,
                to: TransactionBuilder().simulationTransaction(for: message))
        }
    }

    @Test
    func `Signatures with an identity nonce point are rejected`() throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        let signature = try SignedTransferFixture.bytes(SignedTransferFixture.identityNonceSignature)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(byAdding: signature,
                for: TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message)).accounts[0].address,
                to: TransactionBuilder().simulationTransaction(for: message))
        }
    }

    @Test(arguments: [0, 63, 65])
    func `Transaction assembly rejects incomplete signature fields`(_ count: Int) throws {
        let message = try SignedTransferFixture.bytes(SignedTransferFixture.message)

        #expect(throws: ValidationError.invalidSignature) {
            try TransactionBuilder().transaction(byAdding: Data(repeating: 0, count: count),
                for: Address(SignedTransferFixture.sender), to: TransactionBuilder().simulationTransaction(for: message))
        }
    }

    @Test(arguments: [
        ("empty", ValidationError.invalidMessage),
        ("legacy", .invalidMessage),
        ("v0", .invalidMessage),
        ("too many signers", .invalidMessage),
        ("readonly signer", .invalidTransaction),
        ("truncated accounts", .invalidTransaction),
        ("oversized", .invalidMessage),
    ])
    func `Transaction assembly rejects unsupported message headers and sizes`(_ input: String, expectedError: ValidationError) throws {
        var message = try SignedTransferFixture.bytes(SignedTransferFixture.message)
        switch input {
        case "empty": message = Data()
        case "legacy": message[0] = 1
        case "v0": message[0] = 0x80
        case "too many signers": message[1] = 13
        case "readonly signer": message[2] = 1
        case "truncated accounts": message = Data(message.prefix(73))
        default: message = Data(message + Data(repeating: 0, count: 4_096))
        }

        #expect(throws: expectedError) {
            try TransactionBuilder().simulationTransaction(for: message)
        }
    }
}
