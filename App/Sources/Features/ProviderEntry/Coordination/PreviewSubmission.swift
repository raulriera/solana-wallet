/// A submission for previews that shows a fixed rejection.
struct PreviewSubmission<EntryError: ProviderEntryError>: ProviderSubmitting {
    let rejection: EntryError?
    var isPending: Bool { false }

    func submit(_ entry: String) {}
}
