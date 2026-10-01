extension TextRedactor {
    /// Redacts diagnostic text while preserving a simulation's numeric and structural data.
    ///
    /// - Parameter simulation: The simulation diagnostics to sanitize.
    /// - Returns: A simulation with sensitive text replaced by this redactor's policy.
    func redact(_ simulation: SimulateTransaction.Value) -> SimulateTransaction.Value {
        SimulateTransaction.Value(
            error: simulation.error.map { redact($0) },
            logs: simulation.logs.map { $0.map { redact($0) } },
            unitsConsumed: simulation.unitsConsumed,
            loadedAccountsDataSize: simulation.loadedAccountsDataSize,
            fee: simulation.fee,
            replacementBlockhash: simulation.replacementBlockhash.map {
                GetLatestBlockhash.Value(blockhash: redact($0.blockhash), lastValidBlockHeight: $0.lastValidBlockHeight)
            }
        )
    }

    /// Redacts a transaction error's name and any associated text.
    ///
    /// - Parameter error: The transaction error to sanitize.
    /// - Returns: The error with its sensitive text replaced.
    private func redact(_ error: TransactionError) -> TransactionError {
        TransactionError(name: redact(error.name), details: error.details.map { redact($0) })
    }

    /// Redacts nested strings and field names while retaining exact integer values.
    ///
    /// - Parameter detail: The associated transaction-error data to sanitize.
    /// - Returns: The associated data with its sensitive text replaced.
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
