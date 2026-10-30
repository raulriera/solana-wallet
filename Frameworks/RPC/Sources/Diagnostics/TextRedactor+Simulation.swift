extension TextRedactor {
    /// Redacts a simulation's text while keeping its numeric and structural data.
    ///
    /// - Parameter simulation: The simulation diagnostics.
    /// - Returns: The simulation with its text redacted.
    func redact(_ simulation: SimulateTransaction.Value) -> SimulateTransaction.Value {
        SimulateTransaction.Value(
            error: simulation.error.map { redact($0) },
            logs: simulation.logs.map { $0.map { redact($0) } },
            unitsConsumed: simulation.unitsConsumed,
            loadedAccountsDataSize: simulation.loadedAccountsDataSize,
            fee: simulation.fee,
            replacementBlockhash: simulation.replacementBlockhash.map {
                GetLatestBlockhash.Value(blockhash: redact($0.blockhash), lastValidBlockHeight: $0.lastValidBlockHeight)
            },
            preBalances: simulation.preBalances,
            postBalances: simulation.postBalances,
            preTokenBalances: simulation.preTokenBalances,
            postTokenBalances: simulation.postTokenBalances
        )
    }

    /// Redacts a transaction error's name and details.
    ///
    /// - Parameter error: The transaction error.
    /// - Returns: The error with its text redacted.
    private func redact(_ error: TransactionError) -> TransactionError {
        TransactionError(name: redact(error.name), details: error.details.map { redact($0) })
    }

    /// Redacts the strings and field names in transaction-error data.
    ///
    /// - Parameter detail: The transaction-error data.
    /// - Returns: The data with its text redacted.
    private func redact(_ detail: TransactionError.Detail) -> TransactionError.Detail {
        switch detail {
        case .string(let value):
            .string(redact(value))
        case .integer:
            detail
        case .array(let values):
            .array(values.map { redact($0) })
        case .object(let values):
            .object(values.reduce(into: [:]) { result, entry in
                result[redact(entry.key)] = redact(entry.value)
            })
        }
    }
}
