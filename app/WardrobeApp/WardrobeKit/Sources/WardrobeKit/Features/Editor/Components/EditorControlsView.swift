import DesignSystem
import PhotosUI
import SwiftUI

/// X top-left, tool rail top-right, Save + Share + the completing checkmark
/// along the bottom.
struct EditorControlsView: View {
    let isSaving: Bool
    let didSave: Bool
    let isExporting: Bool
    let isCompleting: Bool
    let onClose: () -> Void
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onText: () -> Void
    let onSticker: () -> Void
    let onPickPhoto: (Data) -> Void
    let onBackground: () -> Void
    let onDrawing: () -> Void
    let onLayers: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onComplete: () -> Void

    /// Held here rather than in the view model: it is the picker's own
    /// transport, and it is cleared the moment the bytes are read.
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                MediaCircleButtonView(systemName: "xmark", action: onClose)
                    .accessibilityLabel(Text("common.close", bundle: .module))

                Spacer()

                HistoryControlsView(
                    canUndo: canUndo, canRedo: canRedo, onUndo: onUndo, onRedo: onRedo
                )

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
                .accessibilityIdentifier("editor.tool.text")
            MediaCircleButtonView(systemName: "face.smiling", action: onSticker)
                .accessibilityLabel(Text("editor.tool.sticker", bundle: .module))
                .accessibilityIdentifier("editor.tool.sticker")
            photoPicker
            MediaCircleButtonView(systemName: "paintpalette", action: onBackground)
                .accessibilityLabel(Text("editor.tool.background", bundle: .module))
                .accessibilityIdentifier("editor.tool.background")
            MediaCircleButtonView(systemName: "pencil.tip", action: onDrawing)
                .accessibilityLabel(Text("editor.tool.drawing", bundle: .module))
                .accessibilityIdentifier("editor.tool.drawing")
            MediaCircleButtonView(systemName: "square.3.layers.3d", action: onLayers)
                .accessibilityLabel(Text("editor.tool.layers", bundle: .module))
                .accessibilityIdentifier("editor.tool.layers")
        }
    }

    /// `PhotosPicker` rather than the app's own library grid: it runs out of
    /// process, so it asks for no photo-library permission at all and cannot
    /// see anything the user did not pick (§18.2). The grid earns its
    /// authorization by browsing; sticking one photo on a canvas does not.
    private var photoPicker: some View {
        PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .current) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel(Text("editor.tool.photo", bundle: .module))
        .accessibilityIdentifier("editor.tool.photo")
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                EditorHaptics.commit.play()
                onPickPhoto(data)
            }
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
        // §19: a state may not be carried by a glyph alone, and swapping the
        // icon for a checkmark is exactly that.
        .accessibilityValue(didSave ? Text("editor.saved", bundle: .module) : Text(verbatim: ""))
        .accessibilityIdentifier("editor.save")
    }

    private var sharePill: some View {
        Button(action: onShare) {
            HStack(spacing: Spacing.sm) {
                if isExporting {
                    ProgressView()
                        .tint(AppColor.onMedia)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text("editor.share", bundle: .module)
            }
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
        }
        // PRD §17: prevent duplicate export actions.
        .disabled(isExporting)
        .accessibilityLabel(Text("editor.share", bundle: .module))
        .accessibilityIdentifier("editor.share")
    }

    /// FR-028: the checkmark is the only action that completes the challenge.
    private var completeButton: some View {
        Button(action: onComplete) {
            Group {
                if isCompleting {
                    ProgressView()
                        .tint(AppColor.onMedia)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                }
            }
            .foregroundStyle(AppColor.onMedia)
            .frame(width: 56, height: 56)
            .background(AppColor.accent, in: Circle())
        }
        // The double-tap guard already lives in `completeChallenge()`; this is
        // so the wait for the garment scan is visible rather than silent.
        .disabled(isCompleting)
        .accessibilityLabel(Text("editor.complete", bundle: .module))
        .accessibilityIdentifier("editor.complete")
    }
}

// Crop tool with its own Cancel/Done bar, dark styled.
