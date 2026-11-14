#if os(macOS)
import SwiftUI
import AppKit

enum AppBrand {
    static let displayName = "TranslateDesk"
    static let iconResourceName = "translatedesk-logo"

    static func logoImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: iconResourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let bundleNames = [
            "TranslateDesk_TranslateDesk.bundle",
            "TranslateDesk_TranslateDesk.resources"
        ]
        let roots = [
            Bundle.main.bundleURL,
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent()
        ].compactMap { $0 }

        for root in roots {
            for bundleName in bundleNames {
                let bundleURL = root.appendingPathComponent(bundleName)
                if let bundle = Bundle(url: bundleURL),
                   let url = bundle.url(forResource: iconResourceName, withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }
        return nil
    }
}

struct AppLogoMark: View {
    var size: CGFloat = 40
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Group {
            if let nsImage = AppBrand.logoImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "character.book.closed.fill")
                            .font(.system(size: size * 0.44, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? max(8, size * 0.24)
    }
}
#endif
