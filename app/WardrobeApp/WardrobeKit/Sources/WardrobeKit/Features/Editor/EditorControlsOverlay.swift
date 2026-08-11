import DesignSystem
import SwiftUI

/// X top-left, tool rail top-right, Save + Share + the completing checkmark
/// along the bottom.
struct EditorControlsOverlay: View {
    let isSaving: Bool
    let didSave: Bool
    let onClose: () -> Void
    let onText: () -> Void
    let onSticker: () -> Void
    let onCrop: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                MediaCircleButton(systemName: "xmark", action: onClose)
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
            MediaCircleButton(systemName: "textformat", action: onText)
                .accessibilityLabel(Text("editor.addText", bundle: .module))
            MediaCircleButton(systemName: "face.smiling", action: onSticker)
                .accessibilityLabel(Text("editor.tool.sticker", bundle: .module))
            MediaCircleButton(systemName: "crop", action: onCrop)
                .accessibilityLabel(Text("editor.tool.crop", bundle: .module))
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

/// Crop tool with its own Cancel/Done bar, dark styled.
struct CropStageView: View {
    let image: CGImage?
    let spec: CropSpec
    let onChange: (CropSpec) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("common.cancel", bundle: .module)
                        .frame(minHeight: 44)
                }

                Spacer()

                Button(action: onDone) {
                    Text("common.done", bundle: .module)
                        .bold()
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)

            CropToolView(image: image, spec: spec, onChange: onChange)
                .padding(Spacing.lg)
        }
    }
}

struct EditorLoadFailedView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("common.errorTitle", bundle: .module)
            } icon: {
                Image(systemName: "photo.badge.exclamationmark")
            }
        } description: {
            Text(error.userMessage)
        } actions: {
            Button(action: onRetry) {
                Text("common.retry", bundle: .module)
            }
        }
    }
}
