import Foundation

/// What the image-detail OCR pane should present for a given clip.
///
/// The persisted `OCRStatus` alone cannot drive the UI: `.pending` is a
/// capture-time eligibility marker (`ClipItem.init`), not evidence that any
/// OCR work exists. This resolver combines the stored status with real
/// execution evidence (`ocrUpdatedAt`) and the current auto-process setting
/// to derive a presentation state where spinners only appear while Vision is
/// genuinely running.
enum OCRDetailState: Equatable {
    /// Never attempted and nothing scheduled: quiet call-to-action. Covers
    /// every textless `.pending` row — the coordinator has no per-item queued
    /// marker, so a preference toggle alone must never imply future work.
    case idle
    /// Vision recognition is actually running.
    case processing
    /// Recognized text is available.
    case ready
    /// Recognition ran to completion and found no text.
    case empty
    /// Recognition ran and failed.
    case failed
}

struct OCRDetailPresentation: Equatable {
    let state: OCRDetailState
    /// Spinner only for real in-flight work (never for waiting/idle).
    let showsSpinner: Bool
    /// Whether the header offers the manual recognition action. Hidden while
    /// work is pending/running so users cannot re-trigger a coalesced task.
    let showsManualAction: Bool
    /// true → “重新识别” (a run already happened); false → “识别文字” (first run).
    let usesRetryLabel: Bool

    /// Pure resolution of the OCR pane presentation.
    ///
    /// - Parameters:
    ///   - status: persisted `resolvedOCRStatus`.
    ///   - hasText: non-empty `ocrText`.
    ///   - hasAttempted: `ocrUpdatedAt != nil` — every execution path stamps it,
    ///     so nil reliably means "never attempted".
    ///
    /// Deliberately takes NO preference toggles: execution state cannot be
    /// inferred from settings, only from real status/timestamp evidence.
    static func resolve(
        status: OCRStatus,
        hasText: Bool,
        hasAttempted: Bool
    ) -> OCRDetailPresentation {
        func presentation(
            _ state: OCRDetailState,
            spinner: Bool = false,
            manualAction: Bool = true,
            retryLabel: Bool = true
        ) -> OCRDetailPresentation {
            OCRDetailPresentation(
                state: state,
                showsSpinner: spinner,
                showsManualAction: manualAction,
                usesRetryLabel: retryLabel
            )
        }

        if hasText {
            return presentation(.ready)
        }
        switch status {
        case .processing:
            return presentation(.processing, spinner: true, manualAction: false)
        case .pending:
            // Capture-time eligibility marker only: nothing is queued behind
            // it (the coordinator keeps no per-item queue evidence), so it
            // must present as idle no matter what the toggles say.
            return presentation(.idle, retryLabel: false)
        case .failed:
            return presentation(.failed)
        case .done, .skipped:
            if hasAttempted {
                return presentation(.empty)
            }
            // Legacy rows marked skipped without ever running (e.g. imported
            // before OCR existed): same first-run call-to-action as idle.
            return presentation(.idle, retryLabel: false)
        }
    }
}
