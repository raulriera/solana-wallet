/// An error from validating transaction input.
public enum ValidationError: Error, Sendable, Equatable {
    case invalidAddress
    /// The program-derived address seeds exceed the count or length limits.
    case invalidSeeds
    case addressDerivationFailed
    case invalidBlockhash
    /// The transfer amount is zero.
    case invalidAmount
    case programAddressAsTransferAccount
    case invalidComputeUnitLimit
    case invalidLoadedAccountsDataSizeLimit
    /// The heap size is outside the supported range or isn't a multiple of 1 KiB.
    case invalidHeapSize
    case invalidMessage
    case invalidSignature
    case invalidTransaction
    case unsupportedVersion
    case unsupportedConfiguration
    /// The account has no required signature slot in the message.
    case signerNotRequired
    case signatureAlreadyPresent
}
