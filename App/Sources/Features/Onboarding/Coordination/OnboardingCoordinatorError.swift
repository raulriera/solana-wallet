/// An onboarding failure that never retains underlying errors or recovery text.
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
}
