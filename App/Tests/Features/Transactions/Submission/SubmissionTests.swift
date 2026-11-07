import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@Suite(.serialized)
struct SubmissionTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test
    func `Submission sends the signed bytes once with finalized preflight`() async throws {
        let signed = try ExternalFixture.signedResult()
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(ExternalFixture.signature)]])

        let result = try await Submitter(rpc: accepted.client).submit(signed)

        #expect(result.signature == ExternalFixture.signature)
        let requests = await accepted.requests
        try #require(requests.count == 1)
        #expect(try requests[0].rpcMethod == "sendTransaction")
        #expect(try requests[0].rpcParameters[0] as? String == signed.transaction.serializedRepresentation.base64EncodedString())
        #expect(try (requests[0].rpcParameters[1] as? [String: Any])?["preflightCommitment"] as? String == "finalized")
    }

    @Test
    func `A rate-limited submission keeps its receipt and rate-limit details`() async throws {
        let signed = try ExternalFixture.signedResult()
        let limited = HTTPResponses([:], error: Self.rateLimit)

        let error = try await #require(throws: DeliveryError.self) {
            try await Submitter(rpc: limited.client).submit(signed)
        }

        #expect(error.submission.signature == ExternalFixture.signature)
        #expect(error.submission.network == .devnet)
        #expect(error.cause as? RPCError == Self.rateLimit)
        #expect(await limited.requests.count == 1)
    }

    @Test
    func `A mismatched acknowledgment is rejected`() async throws {
        let signed = try ExternalFixture.signedResult()
        let mismatched = HTTPResponses(["sendTransaction": [#""another-signature""#]])

        let error = try await #require(throws: DeliveryError.self) {
            try await Submitter(rpc: mismatched.client).submit(signed)
        }

        #expect(error.cause as? SubmitterError == .responseMismatch(expectedSignature: ExternalFixture.signature))
        #expect(await mismatched.requests.count == 1)
    }

    @Test
    func `A local receipt carries the reviewed last valid block height`() async throws {
        let fixture = try SigningFixture()
        let checks = try HTTPResponses.signing()
        let signed = try await Signer(validator: PreparationValidator(rpc: checks.client), store: SigningRecoveryStore(recovery: fixture.recovery))
            .sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transaction")
        let signature = try #require(signed.signature)
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(signature)]])

        let receipt = try await Submitter(rpc: accepted.client).submit(signed)

        #expect(receipt == Submission(signature: signature, network: .devnet, lastValidBlockHeight: 550))
    }

    @Test
    func `Submitting a review returns its receipt without waiting for confirmation`() async throws {
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

        let receipt = try await coordinator.submit(simulation)

        #expect(receipt == Submission(signature: ExternalFixture.signature, network: .devnet, lastValidBlockHeight: 650))
        #expect(try await accepted.requests.map { try $0.rpcMethod } == ["sendTransaction"])
        #expect(try await checks.requests.allSatisfy { try $0.rpcMethod != "getSignatureStatuses" })
    }

    @Test(.tags(.network), .timeLimit(.minutes(3)))
    func `Devnet submission delivers 0.001 SOL to the configured recipient`() async throws {
        let rpc = try LiveClients.client(network: .devnet)
        let wallets = try await DevnetWallets.configured()
        let sender = wallets.sender.address
        let recipient = wallets.recipient.address
        try await wallets.requireFunds(1_100_000, using: rpc)
        let coordinator: any TransactionCoordinating = try TransactionCoordinator(
            rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery))
        let initialAccounts = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value]))
        let senderBalance = try #require(initialAccounts.value[0]).lamports
        let recipientBalance = initialAccounts.value[1]?.lamports ?? 0
        let simulation = try await coordinator.simulate([
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000),
            MemoProgram.memo("widgets devnet composition verification", signers: [recipient]),
        ], using: [wallets.sender, wallets.recipient])
        try #require(simulation.diagnostics.value.error == nil)
        let fee = try #require(simulation.fee)
        try #require(fee < 1_000_000)
        #expect(simulation.transaction.instructions.count == 2)
        #expect(simulation.transaction.signatures.count == 2)
        #expect(simulation.balanceChanges == [
            BalanceChange(owner: sender, asset: .sol, before: senderBalance, after: senderBalance - 1_000_000 - fee),
            BalanceChange(owner: recipient, asset: .sol, before: recipientBalance, after: recipientBalance + 1_000_000),
        ])

        let submission = try await coordinator.submit(simulation)
        let result = try await coordinator.confirm(submission)
        try #require(result.outcome == .succeeded)
        let slot = try await result.executionSlot(through: rpc)
        let accounts = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value], minContextSlot: slot))
        #expect(accounts.value[0]?.lamports == senderBalance - 1_000_000 - fee)
        #expect(accounts.value[1]?.lamports == recipientBalance + 1_000_000)
    }

    @Test(.tags(.network), .timeLimit(.minutes(2)))
    func `A devnet RPC rejects a signed transaction from an unfunded wallet`() async throws {
        let rpc = try LiveClients.client(network: .devnet)
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase(wordCount: .twelve)
        let account = try #require(try await wallet.accounts(for: phrase, passphrase: "", paths: [.solana]).first)
        let address = try Address(account.address)
        let blockhash = try await rpc.send(GetLatestBlockhash())
        let message = try MessageBuilder().message(
            instructions: [SystemProgram.transfer(from: address, to: address, lamports: 1)], payer: address,
            recentBlockhash: blockhash.value.blockhash, configuration: configuration()
        )
        let signature = try await wallet.signature(for: message, using: phrase, expectedAddress: address.value,
                                                   passphrase: "", path: .solana)
        let bytes = try TransactionBuilder().transaction(byAdding: signature, for: address,
            to: TransactionBuilder().simulationTransaction(for: message)).serializedRepresentation

        do {
            _ = try await rpc.send(SendTransaction(transaction: bytes))
            Issue.record("An unfunded transaction unexpectedly passed preflight")
        } catch let RPCError.preflight(_, simulation) {
            #expect(simulation.error != nil)
        }
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

        let error = try await #require(throws: DeliveryError.self) {
            try await Submitter(rpc: SolanaRPC(network: .devnet)).submit(input)
        }
        #expect(error.cause as? SubmitterError == .transactionMismatch)
    }

    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)
    }
}
