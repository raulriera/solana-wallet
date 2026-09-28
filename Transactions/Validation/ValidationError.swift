/// A local input error that doesn't include the rejected value in diagnostics.
public enum ValidationError: Error, Sendable, Equatable {
    /// The account address isn't ASCII Base58 encoding exactly 32 bytes.
    case invalidAddress
    /// The recent blockhash isn't ASCII Base58 encoding exactly 32 bytes.
    case invalidBlockhash
    /// The transfer amount is zero.
    case invalidAmount
    /// The invoked System Program was supplied as a sender or recipient.
    case programAddressAsTransferAccount
    /// The compute unit limit is outside the supported range.
    case invalidComputeUnitLimit
    /// The loaded account data size limit is outside the supported range.
    case invalidLoadedAccountsDataSizeLimit
    /// The heap size is outside the supported range or isn't a multiple of 1 KiB.
    case invalidHeapSize
    /// The message header or size doesn't support a single-signer V1 transaction.
    case invalidMessage
    /// The signature isn't 64 bytes or doesn't verify against the message's signer.
    case invalidSignature
    /// The complete V1 envelope has invalid framing, bounds, accounts, or indices.
    case invalidTransaction
    /// The envelope isn't encoded in the supported V1 transaction format.
    case unsupportedVersion
    /// The message uses configuration bits whose meaning isn't supported.
    case unsupportedConfiguration
    /// The selected account doesn't have a required signature slot in this message.
    case signerNotRequired
    /// The selected account's signature slot is already occupied.
    case signatureAlreadyPresent
}
