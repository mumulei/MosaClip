import AppKit
import SwiftUI

struct ColorPreviewView: View {
    let sourceText: String
    let parsed: ParsedColor
    var compact = false
    var onEdit: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: compact ? 12 : 16) {
                swatchControl

                Text(sourceText)
                    .font(.system(size: compact ? 13 : 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                VStack(spacing: compact ? 5 : 7) {
                    ForEach(ColorFormat.allCases, id: \.self) { format in
                        formatRow(format)
                    }
                }
                .frame(maxWidth: compact ? 430 : 560)
            }
            .padding(compact ? 12 : 20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var swatchControl: some View {
        if let onEdit {
            Button(action: onEdit) {
                swatch
            }
            .buttonStyle(.plain)
            .help(L10n.tr("action.edit"))
            .accessibilityLabel(L10n.tr("action.edit"))
            .accessibilityValue(parsed.formatted(.rgba))
        } else {
            swatch
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.tr("type.color"))
                .accessibilityValue(parsed.formatted(.rgba))
        }
    }

    private var swatch: some View {
        ZStack {
            TransparencyCheckerboard(squareSize: compact ? 8 : 12)
            Color(nsColor: parsed.nsColor)
        }
        .frame(width: compact ? 88 : 180, height: compact ? 72 : 120)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 16)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(
            color: Color(nsColor: parsed.nsColor).opacity(compact ? 0.22 : 0.3),
            radius: compact ? 7 : 14,
            y: compact ? 3 : 6
        )
    }

    private func formatRow(_ format: ColorFormat) -> some View {
        let value = parsed.formatted(format)
        return HStack(spacing: 10) {
            Text(format.rawValue)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 36 : 44, alignment: .leading)

            Text(value)
                .font(.system(size: compact ? 11 : 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(value, forType: .string)
                ToastCenter.shared.show(
                    ToastDescriptor(message: L10n.tr("action.copied"), icon: .success)
                )
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help(L10n.tr("cmd.copyAs", format.rawValue))
            .accessibilityLabel(L10n.tr("cmd.copyAs", format.rawValue))
        }
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TransparencyCheckerboard: View {
    let squareSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(Color.primary.opacity(0.08)))
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityHidden(true)
    }
}
