import DesignSystem
import PhotosUI
import SwiftUI

struct RegenerateIllustrationView: View {
    let cutout: Data?
    let original: Data?
    let viewModel: WardrobeItemDetailViewModel
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var pickedItem: PhotosPickerItem?

    private var references: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            reference(cutout, caption: "wardrobe.detail.regenerate.cutout")

            if original != nil {
                reference(original, caption: "wardrobe.detail.regenerate.original")
            }

            addPhotoTile
        }
    }

    private var addPhotoTile: some View {
        VStack(spacing: Spacing.xs) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppColor.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .overlay {
                        if viewModel.isScanningPhoto {
                            ProgressView()
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(AppFont.title)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
            }

            Text("wardrobe.detail.regenerate.addPhoto", bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private var candidates: some View {
        if !viewModel.candidates.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("wardrobe.detail.regenerate.chooseGarment", bundle: .module)
                    .font(AppFont.caption)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(viewModel.candidates) { candidate in
                            candidateTile(candidate)
                        }
                    }
                }
            }
        }
    }

    private func candidateTile(_ candidate: ScannedGarment) -> some View {
        let isChosen = viewModel.chosenCandidateID == candidate.id

        return Button {
            viewModel.chooseCandidate(candidate.id)
        } label: {
            Group {
                if let data = viewModel.thumbnailData(forFile: candidate.cutoutFile) {
                    DownsampledPhotoView(data: data, maxPixel: 300)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(AppColor.surface)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isChosen ? AppColor.accent : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func reference(_ data: Data?, caption: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xs) {
            Group {
                if let data {
                    DownsampledPhotoView(data: data, maxPixel: 600)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColor.surface)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(AppColor.textSecondary)
                        }
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(caption, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                references

                candidates

                Text("wardrobe.detail.regenerate.disclaimer", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("wardrobe.detail.regenerate.note", bundle: .module)
                        .font(AppFont.caption)
                    TextField(
                        String(localized: "wardrobe.detail.regenerate.notePlaceholder", bundle: .module),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("wardrobe.detail.regenerate.note")
                }

                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle(Text("wardrobe.detail.regenerate.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            viewModel.discardCandidates()
                            dismiss()
                        } label: {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onConfirm(note)
                        } label: {
                            Text("wardrobe.detail.regenerate.action", bundle: .module)
                        }
                    }
                }
                .onChange(of: pickedItem) { _, newItem in
                    loadPickedPhoto(newItem)
                }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { pickedItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                viewModel.scanReferencePhoto(data)
            } catch {
                Log.report(error, logger: Log.ui)
            }
        }
    }
}
