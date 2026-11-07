import RPC
import Testing
import Transactions
@testable import Privacy

enum ShieldedPoolOwners {
    static let devnet = [
        "7ry7sotkgSJuxcDZtT5hJJNekqQ4mJQZR5ziBEDpWEij",
        "4RoMdvanfZMnjwmq4NZHCg7pLchiGiUxEF6PfXcggJBS",
        "J8YJWAjWyLFXL5c3sX5GAEKLxN77Xv3sp6kmttuCEJZU",
        "CzbXToxdpS66CmHa3N4c2NfR4NqStAg8tGpqo6pDCprF",
    ]

    static func deposits(of owner: String) async throws -> (recipient: Recipient, deposits: [ShieldedTransaction]) {
        let address = try Address(owner)
        async let records = UserRegistry.recipients(of: [address], using: SolanaRPC(network: .devnet))
        async let batch = Zolana(network: .devnet).shieldedTransactions(taggedWith: [address.bytes], after: nil)
        let recipient = try #require(try await records.first ?? nil)
        let deposits = try await batch.transactions.filter { $0.isProofless && $0.outputs.first?.viewTag == address.bytes }
        try #require(!deposits.isEmpty, "The owner must have a deposit")
        return (recipient, deposits)
    }
}
