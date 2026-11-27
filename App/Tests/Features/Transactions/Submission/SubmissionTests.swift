import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@Suite(.serialized)
struct SubmissionTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
    private static let pending = TransactionOutcome(signature: ExternalFixture.signature, network: .devnet,
                                                    lastValidBlockHeight: 650, status: .pending)

    @Test
    func `Submission sends the signed bytes once with finalized preflight`() async throws {
        let signed = try ExternalFixture.signedResult()
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(ExternalFixture.signature)]])

        let result = try await Submitter(rpc: accepted.client).submit(signed)

        #expect(result == Self.pending)
        let requests = await accepted.requests
        try #require(requests.count == 1)
        #expect(try requests[0].rpcMethod == "sendTransaction")
        #expect(try requests[0].rpcParameters[0] as? String == signed.transaction.serializedRepresentation.base64EncodedString())
        #expect(try (requests[0].rpcParameters[1] as? [String: Any])?["preflightCommitment"] as? String == "finalized")
    }

    @Test
    func `A rate-limited submission keeps its pending outcome`() async throws {
        let signed = try ExternalFixture.signedResult()
        let limited = HTTPResponses([:], error: Self.rateLimit)

        let error = try await #require(throws: DeliveryError.self) {
            try await Submitter(rpc: limited.client).submit(signed)
        }

        #expect(error.outcome == Self.pending)
        #expect(await limited.requests.count == 1)
    }

    @Test
    func `A mismatched acknowledgment is rejected`() async throws {
        let signed = try ExternalFixture.signedResult()
        let mismatched = HTTPResponses(["sendTransaction": [#""another-signature""#]])

        await #expect(throws: DeliveryError.self) {
            try await Submitter(rpc: mismatched.client).submit(signed)
        }

        #expect(await mismatched.requests.count == 1)
    }

    @Test
    func `A local pending outcome carries the reviewed last valid block height`() async throws {
        let fixture = try SigningFixture()
        let checks = try HTTPResponses.signing()
        let signed = try await Signer(validator: PreparationValidator(rpc: checks.client), store: SigningRecoveryStore(recovery: fixture.recovery))
            .sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transaction")
        let signature = try #require(signed.signature)
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(signature)]])

        let outcome = try await Submitter(rpc: accepted.client).submit(signed)

        #expect(outcome == TransactionOutcome(signature: signature, network: .devnet, lastValidBlockHeight: 550,
                                              status: .pending))
    }

    @Test
    func `Submitting a review returns its pending outcome without waiting for confirmation`() async throws {
        let expected = try ExternalFixture.preparation()
        let preparationHTTP = try HTTPResponses.preparation(fixture: expected)
        let checks = try HTTPResponses.signing(fee: 15_000)
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(ExternalFixture.signature)]])
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: preparationHTTP.client, preparer: Preparer(rpc: preparationHTTP.client),
            signer: Signer(validator: PreparationValidator(rpc: checks.client), store: store), submitter: Submitter(rpc: accepted.client),
            confirmer: Confirmer(rpc: checks.client)
        )
        let simulation = try await coordinator.simulate(expected.transaction, using: SigningFixture().account)

        let outcome = try await coordinator.submit(simulation)

        #expect(outcome == Self.pending)
        #expect(try await accepted.requests.map { try $0.rpcMethod } == ["sendTransaction"])
        #expect(try await checks.requests.allSatisfy { try $0.rpcMethod != "getSignatureStatuses" })
    }

    @Test
    func `Partially signed transactions are rejected before submission`() async throws {
        let signed = try ExternalFixture.signedResult(hasPayerSignature: false)
        let rpc = SolanaRPC(network: .devnet)

        await #expect(throws: SubmitterError.missingSignatures) {
            try await Submitter(rpc: rpc).submit(signed)
        }
    }

    @Test
    func `Replacing an existing cosigner signature prevents submission`() async throws {
        let signed = try ExternalFixture.signedResult()
        let original = signed.transaction
        let replacement = try #require(Data(base64Encoded: ExternalFixture.alternatePayerSignature))
        let altered = Transaction(message: original.message, lifetimeSpecifier: original.lifetimeSpecifier,
                                  accounts: original.accounts, requests: original.requests,
                                  instructions: original.instructions, signatures: [replacement, original.signatures[1]])
        let input = SignedTransaction(preparation: signed.preparation, transaction: altered)

        let unused = HTTPResponses([:])

        await #expect(throws: DeliveryError.self) {
            try await Submitter(rpc: unused.client).submit(input)
        }
        #expect(await unused.requests.isEmpty)
    }
}
