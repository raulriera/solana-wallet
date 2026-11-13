import CoreImage.CIFilterBuiltins
import SwiftUI

/// Shows text as a QR code with sharp modules at any size.
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = CGImage.qrCode(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }
}

private extension CGImage {
    /// Creates a QR code that encodes text, one pixel for each module, with a one-module quiet zone.
    ///
    /// - Parameter text: The text to encode.
    /// - Returns: The QR code, or `nil` when the text doesn't fit in one.
    static func qrCode(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        return filter.outputImage.flatMap { CIContext().createCGImage($0, from: $0.extent) }
    }
}

#Preview {
    QRCode(text: "6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        .padding()
}
