import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@Suite(.serialized)
struct SubmissionTests {
    @Test
    func `One rate-limited route does not prevent another route accepting the transaction`() async throws {
        let signed = try ExternalFixture.signedResult()
        let checks = try HTTPResponses.signing(fee: 15_000)
        let limited = HTTPResponses([:], error: .http(statusCode: 429, retryAfter: "3"))
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(ExternalFixture.signature)]])

        let result = try await Submitter(rpcs: [limited.client, accepted.client]).submit(signed)

        #expect(result.signature == ExternalFixture.signature)
        for transport in [limited, accepted] {
            let requests = await transport.requests
            try #require(requests.count == 1)
            #expect(try requests[0].rpcParameters[0] as? String == signed.transaction.serializedRepresentation.base64EncodedString())
            #expect(try (requests[0].rpcParameters[1] as? [String: Any])?["preflightCommitment"] as? String == "finalized")
        }
    }

    @Test
    func `Sending reads nothing before dispatch`() async throws {
        let signed = try ExternalFixture.signedResult()
        let reads = HTTPResponses([:])
        let accepted = HTTPResponses(["sendTransaction": [try HTTPResponses.json(ExternalFixture.signature)]])

        _ = try await Submitter(rpcs: [accepted.client]).submit(signed)

        #expect(await reads.requests.isEmpty)
        #expect(try await accepted.requests.map { try $0.rpcMethod } == ["sendTransaction"])
    }

    @Test
    func `Failed routes retain rate-limit details and reject a mismatched acknowledgment`() async throws {
        let signed = try ExternalFixture.signedResult()
        let checks = try HTTPResponses.signing(fee: 15_000)
        let limited = HTTPResponses([:], error: .http(statusCode: 429, retryAfter: "3"))
        let mismatched = HTTPResponses(["sendTransaction": [#""another-signature""#]])

        let error = try await #require(throws: DeliveryError.self) {
            try await Submitter(rpcs: [limited.client, mismatched.client]).submit(signed)
        }
        let rejection = try #require(error.cause as? Submitter.Rejection)
        #expect(error.submission.signature == ExternalFixture.signature)
        #expect(error.submission.network == .devnet)
        #expect(rejection.errors.count == 2)
        #expect(rejection.errors.contains { $0 as? RPCError == .http(statusCode: 429, retryAfter: "3") })
        #expect(rejection.errors.contains {
            $0 as? SubmitterError == .responseMismatch(expectedSignature: ExternalFixture.signature)
        })
        #expect(await limited.requests.count == 1)
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

        let receipt = try await Submitter(rpcs: [accepted.client]).submit(signed)

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
            signer: Signer(validator: PreparationValidator(rpc: checks.client), store: store), submitter: Submitter(rpcs: [accepted.client]),
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
        let rpcs = try LiveClients.devnetRPCs()
        let wallets = try await DevnetWallets.configured()
        let sender = wallets.sender.address
        let recipient = wallets.recipient.address
        try await fund(sender.value, using: rpcs)
        let coordinator: any TransactionCoordinating = try TransactionCoordinator(
            rpc: rpcs[0], store: SigningRecoveryStore(recovery: wallets.recovery), rpcs: rpcs)
        let initialAccounts = try await rpcs[0].send(GetMultipleAccounts(addresses: [sender.value, recipient.value]))
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
        for rpc in rpcs {
            let confirmation = try await Confirmer(rpc: rpc).confirm(submission)
            try #require(confirmation.outcome == .succeeded)
            let slot = try await confirmation.executionSlot(through: rpc)
            let accounts = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value], minContextSlot: slot))
            #expect(accounts.value[0]?.lamports == senderBalance - 1_000_000 - fee)
            #expect(accounts.value[1]?.lamports == recipientBalance + 1_000_000)
        }
    }

    @Test(.tags(.network), .timeLimit(.minutes(2)))
    func `Devnet RPCs reject a signed transaction from an unfunded wallet`() async throws {
        let rpcs = try LiveClients.devnetRPCs()
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase(wordCount: .twelve)
        let account = try #require(try await wallet.accounts(for: phrase, passphrase: "", paths: [.solana]).first)
        let address = try Address(account.address)
        let blockhash = try await rpcs[0].send(GetLatestBlockhash())
        let message = try MessageBuilder().message(
            instructions: [SystemProgram.transfer(from: address, to: address, lamports: 1)], payer: address,
            recentBlockhash: blockhash.value.blockhash, configuration: configuration()
        )
        let signature = try await wallet.signature(for: message, using: phrase, expectedAddress: address.value,
                                                   passphrase: "", path: .solana)
        let bytes = try TransactionBuilder().transaction(byAdding: signature, for: address,
            to: TransactionBuilder().simulationTransaction(for: message)).serializedRepresentation

        for rpc in rpcs {
            do {
                _ = try await rpc.send(SendTransaction(transaction: bytes))
                Issue.record("An unfunded transaction unexpectedly passed preflight")
            } catch let RPCError.preflight(_, simulation) {
                #expect(simulation.error != nil)
            }
        }
    }

    @Test
    func `Partially signed transactions are rejected before submission`() async throws {
        let signed = try ExternalFixture.signedResult(hasPayerSignature: false)
        let rpc = Solana(network: .devnet)

        await #expect(throws: SubmitterError.missingSignatures) {
            try await Submitter(rpcs: [rpc]).submit(signed)
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
            try await Submitter(rpcs: [Solana(network: .devnet)]).submit(input)
        }
        #expect(error.cause as? SubmitterError == .transactionMismatch)
    }

    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)
    }

    private func fund(_ address: String, using rpcs: [any RPC & SignatureEventProviding]) async throws {
        let current = try await rpcs[0].send(GetMultipleAccounts(addresses: [address]))
        if let account = current.value.first ?? nil, account.lamports >= 1_010_000 { return }
        for rpc in rpcs {
            do {
                let signature = try await rpc.send(Airdrop(address: address))
                let blockhash = try await rpc.send(GetLatestBlockhash())
                let receipt = Submission(signature: signature, network: .devnet,
                                         lastValidBlockHeight: blockhash.value.lastValidBlockHeight + 150)
                let confirmation = try await Confirmer(rpc: rpc).confirm(receipt)
                if confirmation.outcome == .succeeded { return }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        throw SetupError.fundingUnavailable(address: address)
    }

    private enum SetupError: Error { case fundingUnavailable(address: String) }

    private struct Airdrop: RPCRequest {
        static let method = "requestAirdrop"
        typealias Response = String
        let address: String

        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(address)
            try values.encode(UInt64(10_000_000))
        }
    }
}
