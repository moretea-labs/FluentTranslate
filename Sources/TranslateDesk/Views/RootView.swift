#if os(macOS)
import SwiftUI

/// Two native windows share one AppModel but own their presentation and frame.
struct RootView: View {
    let compact: Bool
    let onCompact: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void
    let onPin: (Bool) -> Void

    var body: some View {
        Group {
            if compact {
                QuickTranslationView(
                    onOpenMain: onExpand,
                    onClose: onClose,
                    onPinnedChange: onPin
                )
                .frame(minWidth: 440, minHeight: 310)
            } else {
                TranslationWorkspaceView(onCompact: onCompact)
                    .frame(minWidth: 820, minHeight: 560)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
