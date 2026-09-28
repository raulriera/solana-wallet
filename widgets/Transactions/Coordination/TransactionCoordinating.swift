/// A wallet workflow with typed preparation, signing, submission, and confirmation operations.
///
/// Signing remains independent of submission; instruction meaning requires separate interpretation.
nonisolated protocol TransactionCoordinating: TransactionPreparing, TransactionSigning, TransactionSubmitting, TransactionConfirming {}
