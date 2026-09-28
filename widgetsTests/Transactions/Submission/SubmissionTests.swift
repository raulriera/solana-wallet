import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Exercises submission through real Helius and public Solana devnet clients.
struct SubmissionTests {
    /// Verifies both RPCs observe the same newly signed transaction after concurrent submission.
    @Test("devnet RPCs submit one signed transfer and confirm the same signature", .timeLimit(.minutes(10)))
    func devnetSubmissionConfirmsOneSignature() async throws {
        let rpcs = try devnetRPCs()
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase()
        let address = try await wallet.address(for: phrase)
        try await fund(address, using: rpcs)
        let sender = try Address(address)
        let transfer = try Transfer(sender: sender, recipient: sender, lamports: 1)
        let preparation = try await Preparer(rpc: rpcs[0]).prepare(transfer, configuration: configuration())
        try #require(preparation.simulation.value.error == nil)
        let signature = try await wallet.signature(for: preparation.message, using: phrase, expectedAddress: address)
        let transaction = try TransactionBuilder().transaction(byAdding: signature, for: sender, to: preparation.bytes)
        let signed = SignedTransaction(preparation: preparation, transaction: transaction)

        let submission = try await Submitter(rpc: rpcs[0], rpcs: rpcs).submit(signed)

        #expect(submission.signature == signed.signature)
        #expect(submission.network == .devnet)
        for rpc in rpcs {
            let confirmation = try await Confirmer(rpc: rpc).confirm(submission)
            #expect(confirmation.outcome == .succeeded)
        }
        print("Devnet submission confirmed by Helius and Solana: \(submission.signature)")
    }

    /// Verifies real validators reject an unfunded payer, independently for each RPC.
    @Test("devnet RPCs reject a signed transaction from an unfunded wallet", .timeLimit(.minutes(2)))
    func devnetRPCsRejectUnfundedPayer() async throws {
        let rpcs = try devnetRPCs()
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase()
        let address = try Address(await wallet.address(for: phrase))
        let blockhash = try await rpcs[0].send(GetLatestBlockhash())
        let message = try MessageBuilder().message(
            for: Transfer(sender: address, recipient: address, lamports: 1),
            recentBlockhash: blockhash.value.blockhash, configuration: configuration()
        )
        let signature = try await wallet.signature(for: message, using: phrase, expectedAddress: address.value)
        let bytes = try TransactionBuilder().transaction(for: message, signature: signature)

        for rpc in rpcs {
            do {
                _ = try await rpc.send(SendTransaction(transaction: bytes))
                Issue.record("An unfunded transaction unexpectedly passed preflight")
            } catch let RPCError.preflight(_, simulation) {
                #expect(simulation.error != nil)
            }
        }
    }

    /// Verifies incomplete local signature slots are rejected with real clients configured.
    @Test("partially signed transactions are rejected before submission")
    func partialSignaturesPreventSubmission() async throws {
        let signed = try ExternalFixture.signedResult(hasPayerSignature: false)
        let rpc = Solana(network: .devnet)

        await #expect(throws: Submitter.Failure.missingSignatures) {
            try await Submitter(rpc: rpc).submit(signed)
        }
    }

    /// Verifies an existing cosigner's approved signature cannot be replaced, even by a valid one.
    @Test("replacing an existing cosigner signature prevents submission")
    func replacingCosignerSignaturePreventsSubmission() async throws {
        let signed = try ExternalFixture.signedResult()
        let original = signed.transaction
        let replacement = try #require(Data(base64Encoded: ExternalFixture.alternatePayerSignature))
        let altered = Transaction(message: original.message, lifetimeSpecifier: original.lifetimeSpecifier,
                                  accounts: original.accounts, requests: original.requests,
                                  instructions: original.instructions, signatures: [replacement, original.signatures[1]])
        let input = SignedTransaction(preparation: signed.preparation, transaction: altered)

        await #expect(throws: Submitter.Failure.transactionMismatch) {
            try await Submitter(rpc: Solana(network: .devnet)).submit(input)
        }
    }

    /// Creates real clients restricted to devnet using a test-runner credential.
    ///
    /// - Returns: Helius and public Solana clients on the same test network.
    /// - Throws: A configuration error when the local API key isn't supplied.
    private func devnetRPCs() throws -> [any RPC] {
        guard let key = ProcessInfo.processInfo.environment["HELIUS_API_KEY"],
              !key.isEmpty, !key.hasPrefix("$(") else { throw SetupFailure.missingAPIKey }
        return [HeliusRPC(apiKey: key, network: .devnet), Solana(network: .devnet)]
    }

    /// Supplies explicit V1 resource limits for a one-lamport transfer to the payer itself.
    ///
    /// - Returns: A zero-priority-fee configuration with enough resources for a native transfer.
    /// - Throws: A validation error if the configuration is invalid.
    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)
    }

    /// Funds a fresh memory-only wallet through the real devnet faucet.
    ///
    /// If both faucets are unavailable, the public address is printed for manual
    /// devnet funding while the recovery phrase remains in this test process only.
    ///
    /// - Parameters:
    ///   - address: The fresh devnet wallet's public address.
    ///   - rpcs: The real devnet clients that can request funding and read its status.
    /// - Throws: A funding or cancellation error; no mainnet RPC is used.
    private func fund(_ address: String, using rpcs: [any RPC]) async throws {
        for rpc in rpcs {
            do {
                let signature = try await rpc.send(Airdrop(address: address))
                let receipt = Submission(signature: signature, network: .devnet)
                let confirmation = try await Confirmer(rpc: rpc).confirm(receipt)
                if confirmation.outcome == .succeeded { return }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("Devnet faucet unavailable: \(error)")
            }
        }
        print("Devnet funding required for memory-only test wallet: \(address)")
        let deadline = ContinuousClock.now.advanced(by: .seconds(480))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(5))
            let accounts = try await rpcs[0].send(GetMultipleAccounts(addresses: [address]))
            if let account = accounts.value.first ?? nil, account.lamports >= 10_000 { return }
        }
        throw SetupFailure.fundingUnavailable
    }

    /// Missing local setup or devnet funding, without including credentials.
    private enum SetupFailure: Error { case missingAPIKey, fundingUnavailable }

    /// A test-only request to the actual devnet faucet; it isn't an app RPC feature.
    private struct Airdrop: RPCRequest {
        static let method = "requestAirdrop"
        typealias Response = String
        let address: String

        /// Encodes the public destination and a small devnet-only funding request.
        ///
        /// - Parameter encoder: The encoder receiving positional RPC parameters.
        /// - Throws: An encoding error if the request cannot be represented.
        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(address)
            try values.encode(UInt64(1_000_000))
        }
    }
}
