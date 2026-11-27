import Foundation
import Transactions

extension Transaction {
    static func fixture(accounts: [Address], instructions: [Instruction] = []) -> Transaction {
        Transaction(message: Data(), lifetimeSpecifier: "11111111111111111111111111111111",
                    accounts: accounts.map { .writable($0) },
                    requests: .init(priorityFeeLamports: nil, computeUnitLimit: nil, loadedAccountsDataSizeLimit: nil,
                                    heapSize: nil),
                    instructions: instructions, signatures: [])
    }
}
