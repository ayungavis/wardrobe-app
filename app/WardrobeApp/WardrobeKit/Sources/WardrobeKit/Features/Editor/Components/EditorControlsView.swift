import DesignSystem
import SwiftUI

/// X top-left, tool rail top-right, Save + Share + the completing checkmark
/// along the bottom.
struct EditorControlsView: View {
    let isSaving: Bool
    let didSave: Bool
    let onClose: () -> Void
    let onText: () -> Void
    let onSticker: () -> Void
    let onCrop: () -> Void
    let onBackground: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                MediaCircleButtonView(systemName: "xmark", action: onClose)
                    .accessibilityLabel(Text("common.close", bundle: .module))

                Spacer()

                toolRail
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                savePill
                sharePill
                Spacer()
                completeButton
            }
        }
        .padding(Spacing.lg)
    }

    private var toolRail: some View {
        VStack(spacing: Spacing.md) {
            MediaCircleButtonView(systemName: "textformat", action: onText)
                .accessibilityLabel(Text("editor.addText", bundle: .module))
            MediaCircleButtonView(systemName: "face.smiling", action: onSticker)
                .accessibilityLabel(Text("editor.tool.sticker", bundle: .module))
            MediaCircleButtonView(systemName: "crop", action: onCrop)
                .accessibilityLabel(Text("editor.tool.crop", bundle: .module))
            MediaCircleButtonView(systemName: "paintpalette", action: onBackground)
                .accessibilityLabel(Text("editor.tool.background", bundle: .module))
                .accessibilityIdentifier("editor.tool.background")
        }
    }

    private var savePill: some View {
        Button(action: onSave) {
            HStack(spacing: Spacing.sm) {
                if isSaving {
                    ProgressView()
                        .tint(AppColor.onMedia)
                } else {
                    Image(systemName: didSave ? "checkmark" : "arrow.down.to.line")
                }
                Text(didSave ? "editor.saved" : "editor.save", bundle: .module)
            }
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .disabled(isSaving || didSave)
        .accessibilityLabel(Text("editor.save", bundle: .module))
    }

    private var sharePill: some View {
        Button(action: onShare) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                Text("editor.share", bundle: .module)
            }
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(Text("editor.share", bundle: .module))
    }

    /// FR-028: the checkmark is the only action that completes the challenge.
    private var completeButton: some View {
        Button(action: onComplete) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 56, height: 56)
                .background(AppColor.accent, in: Circle())
        }
        .accessibilityLabel(Text("editor.complete", bundle: .module))
    }
}

// Crop tool with its own Cancel/Done bar, dark styled.
