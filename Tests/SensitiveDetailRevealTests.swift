import Testing

@testable import PasteMemo

/// Locks the ClipItem-level sensitive reveal policy for the image detail pane:
/// a sensitive image must mask not only the image preview but also its derived
/// OCR text (the `图片 | OCR` tab), while non-sensitive images keep today's UX.
/// Cross-image retention of the selected OCR tab is SwiftUI @State in
/// ClipDetailView and is intentionally untouched by this policy.
@Suite("Sensitive detail reveal")
struct SensitiveDetailRevealTests {
    private func resolve(
        contentType: ClipContentType = .image,
        hasSVGPreview: Bool = false,
        ocrEnabled: Bool = true,
        ocrPaneSelected: Bool = false,
        isSensitive: Bool = false,
        isEditing: Bool = false
    ) -> DetailPresentation {
        ClipDetailView.resolvePresentation(
            contentType: contentType,
            hasSVGPreview: hasSVGPreview,
            ocrEnabled: ocrEnabled,
            ocrPaneSelected: ocrPaneSelected,
            isSensitive: isSensitive,
            isEditing: isEditing
        )
    }

    @Test("Sensitive image masks the OCR tab too")
    func sensitiveImageMasksOCRTab() {
        let presentation = resolve(ocrPaneSelected: true, isSensitive: true)
        #expect(presentation.showsOCRPane)
        #expect(presentation.masksContent)
    }

    @Test("Normal image OCR tab stays unmasked")
    func normalImageOCRTabUnmasked() {
        let presentation = resolve(ocrPaneSelected: true)
        #expect(presentation.showsOCRPane)
        #expect(!presentation.masksContent)
    }

    @Test("Normal image preview tab unchanged")
    func normalImageTabUnmasked() {
        let presentation = resolve()
        #expect(!presentation.showsOCRPane)
        #expect(presentation.showsImagePanePicker)
        #expect(!presentation.masksContent)
    }

    @Test("Sensitive image preview tab stays masked")
    func sensitiveImageTabMasked() {
        let presentation = resolve(isSensitive: true)
        #expect(!presentation.showsOCRPane)
        #expect(presentation.masksContent)
    }

    @Test("OCR processing/failed/empty/retry states live inside the same masked OCR pane")
    func maskingIsIndependentOfOCRStatus() {
        // The mask decision reads no OCR status field; whatever state the OCR
        // pane renders (processing, failed, empty, retryable) it is the same
        // pane and therefore covered by the same decision.
        let presentation = resolve(ocrPaneSelected: true, isSensitive: true)
        #expect(presentation.showsOCRPane && presentation.masksContent)
    }

    @Test("SVG images never show the pane picker or OCR tab")
    func svgImageHasNoOCRTab() {
        let presentation = resolve(hasSVGPreview: true, ocrPaneSelected: true, isSensitive: false)
        #expect(!presentation.showsImagePanePicker)
        #expect(!presentation.showsOCRPane)
        #expect(!presentation.masksContent)

        let sensitive = resolve(hasSVGPreview: true, ocrPaneSelected: true, isSensitive: true)
        #expect(sensitive.masksContent)
    }

    @Test("ocrEnabled=false hides the OCR tab even with stale pane selection")
    func ocrDisabledHidesOCRTab() {
        let presentation = resolve(ocrEnabled: false, ocrPaneSelected: true)
        #expect(!presentation.showsImagePanePicker)
        #expect(!presentation.showsOCRPane)

        let sensitive = resolve(ocrEnabled: false, ocrPaneSelected: true, isSensitive: true)
        #expect(sensitive.masksContent)
    }

    @Test("Editing a sensitive text item unmasks only the editable body")
    func editingUnmasksEditableBodyOnly() {
        let editingText = resolve(
            contentType: .text,
            isSensitive: true,
            isEditing: true
        )
        #expect(!editingText.showsOCRPane)
        #expect(!editingText.masksContent)

        // Unreachable combination (images are not editable), but if it ever
        // happens it must fail closed: stay masked.
        let editingImageFallback = resolve(ocrPaneSelected: true, isSensitive: true, isEditing: true)
        #expect(editingImageFallback.showsOCRPane)
        #expect(editingImageFallback.masksContent)
    }
}
