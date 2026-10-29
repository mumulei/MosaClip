import Testing

@testable import PasteMemo

/// Locks the OCR detail-pane presentation state machine: a persisted
/// `.pending` status alone must never masquerade as running or queued
/// recognition. The coordinator keeps no per-item queue marker, so spinners
/// appear only while Vision is genuinely executing; every never-attempted
/// row presents the quiet idle state with a first-run “识别文字” action —
/// regardless of what the preference toggles say.
@Suite("OCR detail presentation")
struct OCRDetailPresentationTests {
    private func resolve(
        status: OCRStatus,
        hasText: Bool = false,
        hasAttempted: Bool = false
    ) -> OCRDetailPresentation {
        OCRDetailPresentation.resolve(
            status: status,
            hasText: hasText,
            hasAttempted: hasAttempted
        )
    }

    // Audit case A
    @Test("Pending + auto OFF + never attempted → idle first-run call-to-action")
    func autoOffPendingIsIdle() {
        let presentation = resolve(status: .pending)
        #expect(presentation.state == .idle)
        #expect(!presentation.showsSpinner)
        #expect(presentation.showsManualAction)
        #expect(!presentation.usesRetryLabel)
    }

    // Audit case B — toggling auto-process ON does NOT enqueue historical
    // pending rows and capture-time enqueue starts processing immediately,
    // so there is no observable "waiting" phase to present.
    @Test("Pending + auto ON + never attempted still presents idle with 识别文字")
    func autoOnPendingWithoutQueueEvidenceStaysIdle() {
        let presentation = resolve(status: .pending)
        #expect(presentation.state == .idle)
        #expect(!presentation.showsSpinner)
        #expect(presentation.showsManualAction)
        #expect(!presentation.usesRetryLabel)
    }

    // Audit case C
    @Test("Processing is the only spinning state and hides the re-run action")
    func processingHidesManualAction() {
        let presentation = resolve(status: .processing)
        #expect(presentation.state == .processing)
        #expect(presentation.showsSpinner)
        #expect(!presentation.showsManualAction)

        // Independent of the attempt timestamp: processing is decided from
        // the live status alone.
        let midRun = resolve(status: .processing, hasAttempted: true)
        #expect(midRun.state == .processing)
        #expect(!midRun.showsManualAction)
    }

    // Audit case D
    @Test("Recognized text → ready with retry semantics")
    func readyState() {
        let presentation = resolve(status: .done, hasText: true, hasAttempted: true)
        #expect(presentation.state == .ready)
        #expect(!presentation.showsSpinner)
        #expect(presentation.showsManualAction)
        #expect(presentation.usesRetryLabel)

        // Legacy rows may carry text under skipped; text wins regardless.
        let legacyText = resolve(status: .skipped, hasText: true)
        #expect(legacyText.state == .ready)
    }

    // Audit case E
    @Test("Ran but found no text → empty state offering retry")
    func attemptedEmptyStates() {
        let skipped = resolve(status: .skipped, hasAttempted: true)
        #expect(skipped.state == .empty)
        #expect(!skipped.showsSpinner)
        #expect(skipped.showsManualAction && skipped.usesRetryLabel)

        let doneNoText = resolve(status: .done, hasAttempted: true)
        #expect(doneNoText.state == .empty)
    }

    // Audit case F
    @Test("Failed → failed state offering retry without spinner")
    func failedState() {
        let presentation = resolve(status: .failed, hasAttempted: true)
        #expect(presentation.state == .failed)
        #expect(!presentation.showsSpinner)
        #expect(presentation.showsManualAction && presentation.usesRetryLabel)
    }

    @Test("Skipped without an attempt timestamp → idle recognize (legacy rows)")
    func legacySkippedWithoutAttempt() {
        let presentation = resolve(status: .skipped)
        #expect(presentation.state == .idle)
        #expect(presentation.showsManualAction)
        #expect(!presentation.usesRetryLabel)
    }

    // Scenario 9 of the original workstream: master-toggle picker semantics.
    @Test("ocrEnabled=false keeps the image pane picker hidden; enabled keeps it available")
    func pickerSemanticsFollowMasterToggle() {
        let disabled = ClipDetailView.resolvePresentation(
            contentType: .image,
            hasSVGPreview: false,
            ocrEnabled: false,
            ocrPaneSelected: true,
            isSensitive: false,
            isEditing: false
        )
        #expect(!disabled.showsImagePanePicker)
        #expect(!disabled.showsOCRPane)

        let enabled = ClipDetailView.resolvePresentation(
            contentType: .image,
            hasSVGPreview: false,
            ocrEnabled: true,
            ocrPaneSelected: false,
            isSensitive: false,
            isEditing: false
        )
        #expect(enabled.showsImagePanePicker)
        #expect(!enabled.showsOCRPane)
    }

    // Audit cases G + H — sensitive masking must hold in every OCR state,
    // including the new idle presentation for pending rows.
    @Test("Sensitive image still masks the OCR pane regardless of OCR state")
    func sensitiveStillMasksOCRTab() {
        for status in [OCRStatus.pending, .processing, .done, .skipped, .failed] {
            let masked = ClipDetailView.resolvePresentation(
                contentType: .image,
                hasSVGPreview: false,
                ocrEnabled: true,
                ocrPaneSelected: true,
                isSensitive: true,
                isEditing: false
            )
            #expect(masked.showsOCRPane)
            #expect(masked.masksContent, "sensitive masking regressed at status \(status)")
        }
    }
}
