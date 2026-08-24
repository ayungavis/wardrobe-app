import CoreGraphics
import DesignSystem
import PhotosUI
import SwiftUI

struct BackgroundPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let selected: CanvasBackground
    let photo: (UUID) -> CGImage?
    let onPick: (CanvasBackground) -> Void
    let onPickPhoto: (Data) -> Void

    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.md) {
                    photoTile
                    ForEach(CanvasBackground.Palette.allCases) { palette in
                        swatchButton(.palette(palette))
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("editor.background.title", bundle: .module)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppColor.onMedia)

                Text("editor.background.subtitle", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onMedia.opacity(0.64))
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
                    .foregroundStyle(AppColor.onMedia)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
        }
    }

    private var isPhotoSelected: Bool {
        selected.photoID != nil
    }

    private var photoTile: some View {
        PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .current) {
            BackgroundTileView(
                artwork: isPhotoSelected ? .background(selected) : .emptyPhotoSlot,
                photo: photo,
                title: Text("editor.background.photo", bundle: .module),
                isSelected: isPhotoSelected
            )
        }
        .accessibilityLabel(Text("editor.background.choosePhoto", bundle: .module))
        .accessibilityIdentifier("editor.background.photo")
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

    private func swatchButton(_ background: CanvasBackground) -> some View {
        Button {
            EditorHaptics.selection.play()
            onPick(background)
        } label: {
            BackgroundTileView(
                artwork: .background(background),
                photo: photo,
                title: Text(verbatim: background.name),
                isSelected: background == selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: background.name))
        .accessibilityAddTraits(background == selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier(for: background))
    }

    private func identifier(for background: CanvasBackground) -> String {
        switch background {
        case let .palette(palette): "editor.background.\(palette.rawValue)"
        case .photo: "editor.background.photo"
        }
    }
}

private struct BackgroundTileView: View {
    enum Artwork {
        case background(CanvasBackground)
        case emptyPhotoSlot
    }

    let artwork: Artwork
    let photo: (UUID) -> CGImage?
    let title: Text
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            fill
                .frame(width: 58, height: 92)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSelected ? AppColor.onMedia : AppColor.onMedia.opacity(0.16),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppColor.mediaBackground, AppColor.onMedia)
                            .padding(Spacing.xs)
                    }
                }

            title
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(isSelected ? AppColor.onMedia : AppColor.onMedia.opacity(0.64))
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch artwork {
        case let .background(background):
            CanvasBackgroundView(background: background, photo: photo)
        case .emptyPhotoSlot:
            AppColor.onMedia.opacity(0.12)
                .overlay {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColor.onMedia)
                }
        }
    }
}
