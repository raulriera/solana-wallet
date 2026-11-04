import SwiftUI

/// A localized error that says whether repeating the failed step can help.
protocol RetryableError: LocalizedError {
    var canRetry: Bool { get }
}

/// Presents an error in an alert titled by its description and explained by its recovery suggestion.
private struct ErrorAlert<Presented: LocalizedError, Actions: View>: ViewModifier {
    @Environment(\.palette) private var palette
    @Binding var error: Presented?
    let actions: (Presented) -> Actions

    func body(content: Content) -> some View {
        content
            .tint(palette.primary)
            .alert(isPresented: $error.isPresented, error: error, actions: actions) { error in
                Text(error.recoverySuggestion ?? "")
            }
            .tint(nil)
    }
}

extension View {
    /// Presents an error in an alert with an OK button.
    ///
    /// - Parameter error: The error to present, cleared when the alert closes.
    /// - Returns: A view that presents the error in an alert.
    func alert<Presented: LocalizedError>(error: Binding<Presented?>) -> some View {
        alert(error: error) { _ in Button("OK", role: .cancel) {} }
    }

    /// Presents an error in an alert with Try Again and Cancel when retrying can help, or OK otherwise.
    ///
    /// - Parameters:
    ///   - error: The error to present, cleared when the alert closes.
    ///   - retry: The action that repeats the failed step.
    /// - Returns: A view that presents the error in an alert.
    func alert<Presented: RetryableError>(error: Binding<Presented?>, retry: @escaping () -> Void) -> some View {
        alert(error: error) { presented in
            if presented.canRetry {
                Button("Try Again", action: retry)
            }
            Button(presented.canRetry ? "Cancel" : "OK", role: .cancel) {}
        }
    }

    /// Presents an error in an alert with custom buttons.
    ///
    /// - Parameters:
    ///   - error: The error to present, cleared when the alert closes.
    ///   - actions: The alert's buttons for the error.
    /// - Returns: A view that presents the error in an alert.
    func alert<Presented: LocalizedError, Actions: View>(
        error: Binding<Presented?>, @ViewBuilder actions: @escaping (Presented) -> Actions
    ) -> some View {
        modifier(ErrorAlert(error: error, actions: actions))
    }
}
