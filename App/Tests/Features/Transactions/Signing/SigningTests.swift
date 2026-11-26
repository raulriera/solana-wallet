import CryptoKit
import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct SigningTests {
    @Test
    func `An authenticated wallet signs the reviewed message at its last valid block height`() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing(heights: [550, 550])
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let wallet = RecordingWallet()
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: http.client, configuration: fixture.configuration, preparer: Preparer(rpc: (try HTTPResponses.preparation(fixture: fixture.preparation)).client),
            signer: Signer(validator: PreparationValidator(rpc: http.client), store: store, wallet: wallet), submitter: Submitter(rpc: http.client), confirmer: Confirmer(rpc: http.client)
        )

        let preparation = try await coordinator.simulate([fixture.transfer], using: fixture.account)
        #expect(await store.reads.isEmpty)
        let signed = try await coordinator.sign(preparation)

        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(
            Data(base64Encoded: "avQk/DwMx04ex+GYBKContNRuDzLEt0PObiUpqRJYxI=")
        ))
        #expect(signed.serializedRepresentation.dropLast(64) == fixture.message)
        #expect(key.isValidSignature(signed.serializedRepresentation.suffix(64), for: fixture.message))
        #expect(signed.signature != nil)
        #expect(signed.message == preparation.transaction.message)
        #expect(await wallet.messages == [fixture.message])
        let reads = await store.reads
        #expect(reads.count == 1)
        let read = try #require(reads.first)
        #expect(read.recoveryID == fixture.account.recoveryID)
        #expect(read.reason == "Approve transaction")
        let requests = await http.requests
        #expect(requests.count == 3)
        let heights = try requests.filter { try $0.rpcMethod == "getBlockHeight" }
        #expect(heights.count == 2)
        for height in heights {
            let options = try #require(height.rpcParameters.first as? [String: Any])
            #expect(options["commitment"] as? String == "finalized")
            #expect(options["minContextSlot"] as? Int == 402)
        }
        let fee = try #require(requests.first { try $0.rpcMethod == "getFeeForMessage" }).rpcParameters
        #expect(fee[0] as? String == fixture.message.base64EncodedString())
        #expect((fee[1] as? [String: Any])?["commitment"] as? String == "finalized")
    }

    @Test(arguments: ["amount", "message"])
    func `Altered transfer details cannot unlock a wallet for a different message`(_ changed: String) async throws {
        var fixture = try SigningFixture()
        switch changed {
        case "amount":
            fixture.transfer = try SystemProgram.transfer(from: fixture.transfer.accounts[0].address, to: fixture.transfer.accounts[1].address, lamports: 2)
        default:
            fixture.message[fixture.message.count - 8] ^= 1
        }
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: store)

        await #expect(throws: PreparationValidatorError.messageMismatch) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    @Test(arguments: ["failed simulation", "unknown fee", "conflicting fee", "understated fee"])
    func `Failed or inconsistent review results cannot unlock recovery`(_ condition: String) async throws {
        var fixture = try SigningFixture()
        var expected = PreparationValidatorError.inconsistentPreparation
        var error: TransactionError?
        var simulationFee: UInt64? = 10_000
        switch condition {
        case "failed simulation":
            error = .insufficientFundsForFee
            expected = .simulationFailed
        case "unknown fee":
            fixture.fee = .init(context: Context(slot: 401), value: nil)
            expected = .feeUnavailable
        case "conflicting fee": simulationFee = 20_000
        default: fixture.fee = .init(context: Context(slot: 401), value: 1)
        }
        fixture.simulation = .init(context: Context(slot: 402), value: .init(
            error: error, logs: nil, unitsConsumed: nil, loadedAccountsDataSize: nil,
            fee: simulationFee, replacementBlockhash: nil,
            preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
        ))
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: store)

        await #expect(throws: expected) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func `Expired preparations never yield a signature`(expiresDuringAuthentication: Bool) async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing(heights: expiresDuringAuthentication ? [500, 551] : [551])
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let wallet = RecordingWallet()
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: store, wallet: wallet)

        await #expect(throws: PreparationValidatorError.expired) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.count == (expiresDuringAuthentication ? 1 : 0))
        #expect(await wallet.messages.count == (expiresDuringAuthentication ? 1 : 0))
    }

    @Test
    func `An expired review reports its expiry before a changed fee`() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing(heights: [551], fee: 11_000)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: store)

        await #expect(throws: PreparationValidatorError.expired) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.isEmpty)
    }

    @Test(arguments: [UInt64(11_000), nil])
    func `A changed network fee requires another review before unlocking`(_ fee: UInt64?) async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing(fee: fee)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let signer = Signer(validator: PreparationValidator(rpc: http.client), store: store)

        await #expect(throws: PreparationValidatorError.feeChanged) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.isEmpty)
        #expect(await http.requests.count == 2)
    }

    @Test
    func `Denied wallet authentication prevents message signing`() async throws {
        let fixture = try SigningFixture()
        let store = SigningRecoveryStore(recovery: fixture.recovery, error: KeychainStoreError.authenticationFailed)
        let wallet = RecordingWallet()
        let signer = Signer(validator: PreparationValidator(rpc: (try HTTPResponses.signing()).client), store: store, wallet: wallet)

        await #expect(throws: KeychainStoreError.authenticationFailed) {
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }

        #expect(await store.reads.count == 1)
        #expect(await wallet.messages.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling authentication discards late recovery without signing`() async throws {
        let fixture = try SigningFixture()
        let gate = Suspension()
        let store = SigningRecoveryStore(recovery: fixture.recovery, gate: gate)
        let wallet = RecordingWallet()
        let signer = Signer(validator: PreparationValidator(rpc: (try HTTPResponses.signing()).client), store: store, wallet: wallet)
        let operation = Task { @concurrent in
            try await signer.sign(fixture.preparation, for: .account(fixture.account), reason: "Approve transfer")
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await wallet.messages.isEmpty)
    }
}
