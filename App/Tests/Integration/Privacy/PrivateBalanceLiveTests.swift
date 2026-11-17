import ModularArithmetic
import RPC
import Testing
import Transactions
@testable import Privacy

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct PrivateBalanceLiveTests {
    private static let unregistered = "11111111111111111111111111111111"

    @Test
    func `Registry lookups decode every owner's record`() async throws {
        let addresses = try (ShieldedPoolOwners.devnet + [Self.unregistered]).map(Address.init)

        let recipients = try await UserRegistry.recipients(of: addresses, using: SolanaRPC(network: .devnet))

        #expect(recipients.map { $0?.signingAddress.value } == ShieldedPoolOwners.devnet + [nil])
    }

    @Test(arguments: ShieldedPoolOwners.devnet)
    func `Deposits rebuild with the registry's owner hash`(owner: String) async throws {
        let (recipient, deposits) = try await ShieldedPoolOwners.deposits(of: owner)

        let failures = try deposits.flatMap(\.outputs).flatMap { output in
            let payload = try ProoflessOutput(decoding: output.payload)
            let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: output.treeID), leafIndex: output.leafIndex)
            let utxo = UTXO(
                owner: recipient.owner, asset: try #require(PrivateAsset(mintBytes: payload.mint)),
                amount: payload.amount, blinding: blinding, treeID: output.treeID
            )
            let checks = [
                "owner": payload.owner == recipient.owner,
                "blinding": payload.blinding == blinding,
                "UTXO hash": utxo.hash.bigEndianBytes == output.utxoHash,
            ]
            return checks.filter { !$0.value }.map { "leaf \(output.leafIndex) of tree \(output.treeID): \($0.key)" }
        }

        #expect(failures.isEmpty)
    }
}
