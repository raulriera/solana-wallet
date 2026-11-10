import RPC
import Testing
import Transactions
@testable import widgets

extension TransactionCoordinator {
    func run(_ instructions: [Instruction], signedBy signers: [widgets.Account]) async throws -> widgets.Confirmation {
        let simulation = try await simulate(instructions, using: signers)
        try #require(simulation.diagnostics.value.error == nil, "Simulation failed: \(simulation.diagnostics.value.logs ?? [])")
        return try await confirm(submit(simulation))
    }
}
