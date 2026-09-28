import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Exercises submission through real Helius and public Solana devnet clients.
struct SubmissionTests {
    /// Verifies 0.001 SOL reaches a controlled recipient and the remainder returns after fees.
    @Test("devnet submission delivers 0.001 SOL and returns it between retained wallets", .timeLimit(.minutes(10)))
    func devnetSubmissionConfirmsOneSignature() async throws {
        let rpcs = try devnetRPCs()
        let sender = try await DevnetWallets.address(for: DevnetWallets.senderID)
        let recipient = try await DevnetWallets.address(for: DevnetWallets.recipientID)
        try await fund(sender.value, using: rpcs)
        let coordinator = try TransactionCoordinator(rpc: rpcs[0], store: DevnetWallets.store, rpcs: rpcs)
        let initialAccounts = try await rpcs[0].send(GetMultipleAccounts(addresses: [sender.value, recipient.value]))
        let senderBalance = try #require(initialAccounts.value[0]).lamports
        let recipientBalance = initialAccounts.value[1]?.lamports ?? 0
        let transfer = try Transfer(sender: sender, recipient: recipient, lamports: 1_000_000)
        let preparation = try await coordinator.prepare(transfer, configuration: configuration())
        try #require(preparation.simulation.value.error == nil)
        let fee = try #require(preparation.fee.value)
        try #require(fee < transfer.lamports)
        let signed = try await coordinator.sign(preparation, for: DevnetWallets.senderID, reason: "Send 0.001 devnet SOL")

        let submission = try await coordinator.submit(signed)

        #expect(submission.signature == signed.signature)
        #expect(submission.network == .devnet)
        for rpc in rpcs {
            let confirmation = try await Confirmer(rpc: rpc).confirm(submission)
            try #require(confirmation.outcome == .succeeded)
            let accounts = try await rpc.send(GetMultipleAccounts(addresses: [recipient.value],
                                                                  minContextSlot: confirmation.slot))
            let destination = try #require(accounts.value.first ?? nil)
            #expect(destination.lamports == recipientBalance + transfer.lamports)
        }
        print("Devnet delivered 0.001 SOL to \(recipient.value): \(submission.signature)")

        let refund = try Transfer(sender: recipient, recipient: sender, lamports: transfer.lamports - fee)
        let returnPreparation = try await coordinator.prepare(refund, configuration: configuration())
        try #require(returnPreparation.fee.value == fee)
        let returnSigned = try await coordinator.sign(returnPreparation, for: DevnetWallets.recipientID,
                                                       reason: "Return devnet test funds")
        let returned = try await coordinator.submit(returnSigned)
        let confirmation = try await coordinator.confirm(returned)
        try #require(confirmation.outcome == .succeeded)
        let finalAccounts = try await rpcs[0].send(GetMultipleAccounts(
            addresses: [sender.value, recipient.value], minContextSlot: confirmation.slot
        ))
        #expect(finalAccounts.value[0]?.lamports == senderBalance - fee * 2)
        #expect((finalAccounts.value[1]?.lamports ?? 0) == recipientBalance)
        print("Devnet funds returned to retained wallet \(sender.value): \(returned.signature)")
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

    /// Supplies explicit V1 resource limits for a small native transfer.
    ///
    /// - Returns: A zero-priority-fee configuration with enough resources for a native transfer.
    /// - Throws: A validation error if the configuration is invalid.
    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)
    }

    /// Reuses the retained wallet's balance before requesting small devnet faucet funding.
    ///
    /// If both faucets are unavailable, the public address is printed for manual
    /// devnet funding; its recovery is already verified in the protected Vault.
    ///
    /// - Parameters:
    ///   - address: The retained devnet wallet's public address.
    ///   - rpcs: The real devnet clients that can request funding and read its status.
    /// - Throws: A funding or cancellation error; no mainnet RPC is used.
    private func fund(_ address: String, using rpcs: [any RPC]) async throws {
        let current = try await rpcs[0].send(GetMultipleAccounts(addresses: [address]))
        if let account = current.value.first ?? nil, account.lamports >= 1_005_000 { return }
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
        let notice = "Devnet funding required for Vault-retained test wallet: \(address)\n"
        FileHandle.standardError.write(Data(notice.utf8))
        let deadline = ContinuousClock.now.advanced(by: .seconds(480))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(5))
            let accounts = try await rpcs[0].send(GetMultipleAccounts(addresses: [address]))
            if let account = accounts.value.first ?? nil, account.lamports >= 1_005_000 { return }
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
            try values.encode(UInt64(10_000_000))
        }
    }
}
