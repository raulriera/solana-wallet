import CryptoKit
import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

struct ExternalTransactionTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test(arguments: [true, false])
    func `A wallet cosigner preserves supplied bytes and existing signatures`(hasPayerSignature: Bool) async throws {
        let expected = try ExternalFixture.preparation(hasPayerSignature: hasPayerSignature)
        let recovery = try SigningFixture().recovery
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected)
        let signingHTTP = try HTTPResponses.signing(fee: 15_000)
        let store = SigningRecoveryStore(recovery: recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client), signer: Signer(validator: PreparationValidator(rpc: signingHTTP.client), store: store), submitter: Submitter(rpc: signingHTTP.client), confirmer: Confirmer(rpc: signingHTTP.client)
        )
        var input = expected.bytes
        input.insert(0xff, at: input.startIndex)
        input = input.dropFirst()

        let preparation = try await coordinator.simulate(TransactionDecoder().decode(input), using: SigningFixture().account)
        #expect(await store.reads.isEmpty)
        let signed = try await coordinator.sign(preparation)

        #expect(preparation.transaction == expected.transaction)
        #expect(preparation.lastValidBlockHeight == nil)
        #expect(preparation.transaction.serializedRepresentation == input)
        let reference = try ExternalFixture.signed(hasPayerSignature: hasPayerSignature)
        #expect(signed.serializedRepresentation.dropLast(64) == reference.dropLast(64))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(reference.dropFirst(74).prefix(32)))
        #expect(key.isValidSignature(signed.serializedRepresentation.suffix(64), for: preparation.transaction.message))
        #expect(try TransactionBuilder().transaction(byAdding: reference.suffix(64), for: expected.signer, to: input).serializedRepresentation == reference)
        #expect(signed.signatures.allSatisfy { $0.contains(where: { $0 != 0 }) } == hasPayerSignature)
        #expect(await store.reads.count == 1)
        let requests = await preparationHTTP.requests
        #expect(requests.count == 4)
        let validity = try #require(requests.first).rpcParameters
        #expect(validity[0] as? String == expected.transaction.lifetimeSpecifier)
        let simulation = try #require(requests.first { try $0.rpcMethod == "simulateTransaction" }).rpcParameters
        #expect(simulation[0] as? String == input.base64EncodedString())
        for request in requests {
            #expect(try (request.rpcParameters.last as? [String: Any])?["commitment"] as? String == "finalized")
        }
        let checks = try await signingHTTP.requests.filter { try $0.rpcMethod == "isBlockhashValid" }
        #expect(checks.count == 2)
        for check in checks {
            let parameters = try check.rpcParameters
            #expect(parameters[0] as? String == expected.transaction.lifetimeSpecifier)
            let options = try #require(parameters[1] as? [String: Any])
            #expect(options["commitment"] as? String == "finalized")
            #expect(options["minContextSlot"] as? Int == 402)
        }
    }

    @Test
    func `An imported receipt expires 150 blocks after the finalized block height`() async throws {
        let expected = try ExternalFixture.preparation()
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected)
        let signingHTTP = try HTTPResponses.signing(fee: 15_000)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let coordinator = TransactionCoordinator(rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client),
            signer: Signer(validator: PreparationValidator(rpc: signingHTTP.client), store: store), submitter: Submitter(rpc: HTTPResponses([:], error: Self.rateLimit).client),
            confirmer: Confirmer(rpc: signingHTTP.client))

        let simulation = try await coordinator.simulate(expected.transaction, using: SigningFixture().account)

        #expect(simulation.lastValidBlockHeight == nil)
        let error = try await #require(throws: DeliveryError.self) {
            try await coordinator.submit(simulation)
        }
        #expect(error.outcome.lastValidBlockHeight == 650)
        let requests = await preparationHTTP.requests
        #expect(try requests.prefix(2).map { try $0.rpcMethod } == ["isBlockhashValid", "getBlockHeight"])
        let height = try #require(requests.first { try $0.rpcMethod == "getBlockHeight" })
        let options = try #require(height.rpcParameters.first as? [String: Any])
        #expect(options["minContextSlot"] as? Int == 400)
    }

    @Test
    func `An imported review rejects a block height without a representable expiry`() async throws {
        let expected = try ExternalFixture.preparation()
        let http = HTTPResponses([
            "isBlockhashValid": [try HTTPResponses.json(["context": ["slot": 400], "value": true])],
            "getBlockHeight": [String(UInt64.max)],
        ])

        await #expect(throws: PreparerError.expiryOutOfRange) {
            try await Preparer(rpc: http.client).prepare(expected.transaction, for: expected.signer)
        }

        #expect(try await http.requests.map { try $0.rpcMethod } == ["isBlockhashValid", "getBlockHeight"])
    }

    @Test(arguments: [
        "unrelated account", "occupied slot", "invalid cosigner"
    ])
    func `Unrelated signers and invalid or occupied signature slots cannot enter review`(_ condition: String) async throws {
        let expected = try ExternalFixture.preparation()
        let http = try HTTPResponses.preparation(fixture: expected)
        var input = expected.bytes
        var signer = expected.signer
        let error: ValidationError
        switch condition {
        case "unrelated account":
            signer = try #require(expected.transaction.accounts.last).address
            error = .signerNotRequired
        case "occupied slot":
            input = try ExternalFixture.signed()
            error = .signatureAlreadyPresent
        default:
            input[input.count - 128] ^= 1
            error = .invalidSignature
        }

        await #expect(throws: error) { try await Preparer(rpc: http.client).prepare(TransactionDecoder().decode(input), for: signer) }

        #expect(await http.requests.isEmpty)
    }

    @Test
    func `Altered external inspection details cannot unlock recovery`() async throws {
        let expected = try ExternalFixture.preparation()
        let original = expected.transaction
        var accounts = original.accounts
        let account = accounts[1]
        accounts[1] = .init(address: account.address, isSigner: true, isWritable: !account.isWritable)
        let altered = Transaction(
            message: original.message, lifetimeSpecifier: original.lifetimeSpecifier, accounts: accounts,
            requests: original.requests, instructions: original.instructions, signatures: original.signatures
        )
        let preparation = Preparation(source: expected.source, signer: expected.signer, transaction: altered,
                                      network: expected.network, fee: expected.fee, simulation: expected.simulation)
        let http = try HTTPResponses.signing(fee: 15_000)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        await #expect(throws: PreparationValidatorError.messageMismatch) {
            try await Signer(validator: PreparationValidator(rpc: http.client), store: store).sign(preparation, for: .account(SigningFixture().account), reason: "Approve transaction")
        }

        #expect(await http.requests.isEmpty)
        #expect(await store.reads.isEmpty)
    }

    @Test(arguments: ["preparation", "before authentication", "during authentication"])
    func `An unavailable external blockhash stops signing without substitution`(_ stage: String) async throws {
        let expected = try ExternalFixture.preparation()
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected, blockhashValid: stage != "preparation")
        let signingHTTP = try HTTPResponses.signing(fee: 15_000, validities: stage == "during authentication" ? [true, false] : [false])
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let wallet = RecordingWallet()
        let coordinator = TransactionCoordinator(rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client),
            signer: Signer(validator: PreparationValidator(rpc: signingHTTP.client), store: store, wallet: wallet), submitter: Submitter(rpc: signingHTTP.client), confirmer: Confirmer(rpc: signingHTTP.client))

        if stage == "preparation" {
            await #expect(throws: PreparerError.invalidBlockhash) {
                try await coordinator.simulate(expected.transaction, using: SigningFixture().account)
            }
            #expect(await preparationHTTP.requests.count == 1)
        } else {
            let preparation = try await coordinator.simulate(expected.transaction, using: SigningFixture().account)
            await #expect(throws: PreparationValidatorError.expired) {
                try await coordinator.sign(preparation)
            }
        }

        #expect(await wallet.messages.count == (stage == "during authentication" ? 1 : 0))
        #expect(await store.reads.count == (stage == "during authentication" ? 1 : 0))
    }
}
