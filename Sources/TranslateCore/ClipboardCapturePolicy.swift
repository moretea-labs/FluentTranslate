/// Resolves whether a pasteboard update is still the copy initiated for selection capture.
public enum ClipboardCaptureDisposition: Equatable, Sendable {
    case waiting
    case captured
    case superseded
}

/// A stateless policy for rejecting clipboard contents that change while being read.
public enum ClipboardCapturePolicy {
    public static func disposition(
        initialChangeCount: Int,
        observedChangeCount: Int,
        currentChangeCount: Int
    ) -> ClipboardCaptureDisposition {
        guard observedChangeCount != initialChangeCount else { return .waiting }
        return currentChangeCount == observedChangeCount ? .captured : .superseded
    }

    public static func shouldRestoreOriginalClipboardAfterAbort(
        initialChangeCount: Int,
        observedChangeCount: Int,
        currentChangeCount: Int
    ) -> Bool {
        disposition(initialChangeCount: initialChangeCount,
                    observedChangeCount: observedChangeCount,
                    currentChangeCount: currentChangeCount) == .captured
    }
}
