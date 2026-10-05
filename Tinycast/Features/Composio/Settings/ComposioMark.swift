import SwiftUI

/// A toolkit logo, or the first letter when the address is missing or not HTTPS.
struct ComposioMark: View {
    let url: URL?
    let title: String

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        letter
                    }
                }
            } else {
                letter
            }
        }
        .frame(width: Theme.Size.composioAppLogo, height: Theme.Size.composioAppLogo)
        .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
        .accessibilityHidden(true)
    }

    private var letter: some View {
        Text(String(title.first ?? "?"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}
