/// An error in the onboarding workflow.
nonisolated enum OnboardingCoordinatorError: Error, Equatable {
    case operationInProgress
    case draftAlreadyPrepared
    case draftRequired
    case accountRequired
    case preparationFailed
    case discoveryRateLimited
    case recoveryStorageFailed
    case recoveryMismatch
    case accountStorageFailed
    case walletAlreadySaved
}
