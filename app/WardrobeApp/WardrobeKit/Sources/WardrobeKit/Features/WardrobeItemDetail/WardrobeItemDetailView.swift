import DesignSystem
import SwiftUI

public struct WardrobeItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WardrobeItemDetailViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditing: Bool = false

    @State private var editableName: String = ""
    @State private var editableDescription: String = ""

    private let onDeleted: () -> Void

    public init(viewModel: WardrobeItemDetailViewModel, onDeleted: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDeleted = onDeleted
    }

//    public var body: some View {
//                        name: item.name,
//                        category: item.category,
//                        status: item.status,
//                        wearCount: viewModel.wearCount,
//                        firstWornAt: viewModel.firstWornAt,
//                        lastWornAt: viewModel.lastWornAt
//                    timeline
//                    similar
//                    deleteButton
//        #if os(iOS)
//        #endif
//                isPresented: $isDeleteConfirmationPresented,
//                titleVisibility: .visible
//                    viewModel.delete()
//                // FR-018.14: the consequence is stated before the red button,
//                // not discovered after it.
    public var body: some View {
        ZStack {
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let item = viewModel.item {
                        HeroView(
                            data: viewModel.thumbnailData(for: item),
                            isEditing: isEditing
                        )
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.xl)

                        Text("wardrobe.wearCount \(viewModel.wearCount)", bundle: .module)
                            .font(AppFont.title)
                            .fontWeight(.black)
                            .stroke(color: .white, width: 3)
                            .padding(.top, Spacing.lg)
                            .zIndex(2)

                        EditableInfoCardView(
                            isEditing: isEditing,
                            name: $editableName,
                            description: $editableDescription,
                            lastWornAt: viewModel.lastWornAt
                        )
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)

                        if isEditing {
                            Button(role: .destructive) {
                                isDeleteConfirmationPresented = true
                            } label: {
                                Image(systemName: "trash.circle")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.black)
                            }
                            .padding(.top, Spacing.lg)
                        }

                        if !isEditing {
                            VStack(spacing: Spacing.xl) {
                                timeline
                                similar
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.xl)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isEditing {
                            viewModel.updateItem(name: editableName, description: editableDescription)
                        }
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
            }
        }
        .task {
            viewModel.load()
        }
        .onChange(of: viewModel.item) { _, newItem in
            if let item = newItem {
                editableName = item.name
                editableDescription = item.description
            }
        }
        .onChange(of: viewModel.isDeleted) { _, deleted in
            if deleted {
                onDeleted()
                dismiss()
            }
        }
        .confirmationDialog(
            Text("wardrobe.detail.delete.title", bundle: .module),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) { viewModel.delete() } label: { Text("wardrobe.detail.delete.action", bundle: .module) }
            Button(role: .cancel) {} label: { Text("common.cancel", bundle: .module) }
        } message: {
            Text("wardrobe.detail.delete.message", bundle: .module)
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if !viewModel.wears.isEmpty {
            SectionView(title: "wardrobe.detail.timeline") {
                WearTimelineView(wears: viewModel.wears)
            }
        }
    }

    private var similar: some View {
        SectionView(title: "wardrobe.detail.similar") {
            if viewModel.similar.isEmpty {
                Text("wardrobe.detail.similar.empty", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(viewModel.similar) { entry in
                            SimilarItemCellView(
                                entry: entry,
                                data: viewModel.thumbnailData(for: entry.item)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private struct HeroView: View {
        let data: Data?
        let isEditing: Bool

        var body: some View {
            Group {
                if let data {
                    DownsampledPhotoView(data: data)
                } else {
                    Image(systemName: "tshirt")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private struct EditableInfoCardView: View {
        let isEditing: Bool
        @Binding var name: String
        @Binding var description: String
        let lastWornAt: Date?

        var body: some View {
            ZStack(alignment: .top) {
                Image("WardrobeItemDetail", bundle: .module)
                    .resizable()

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        label("wardrobe.detail.name")
                        if isEditing {
                            TextField(String(localized: "wardrobe.detail.name", bundle: .module), text: $name)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                                .onSubmit {}
                        } else {
                            Text(name)
                        }
                    }

                    Divider()

                    HStack {
                        label("wardrobe.detail.lastWorn")
                        Text(lastWornText(lastWornAt))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        label("wardrobe.detail.description")
                        if isEditing {
                            TextEditor(text: $description)
                                .frame(minHeight: 60)
                                .padding(4)
                                .scrollContentBackground(.hidden)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text(description.isEmpty ? " " : description)
                                .frame(minHeight: 60, alignment: .topLeading)
                        }
                    }
                }
                .font(AppFont.body)
                .foregroundColor(.black)
                .padding(.top, 40)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }

        private func label(_ key: LocalizedStringKey) -> Text {
            Text(key, bundle: .module).bold() + Text(verbatim: " :").bold()
        }

        private func lastWornText(_ date: Date?) -> String {
            guard let date else { return String(localized: "wardrobe.detail.never", bundle: .module) }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

private struct SimilarItemCellView: View {
    let entry: SimilarItem
    let data: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let data {
                    DownsampledPhotoView(data: data)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(AppColor.surface)
                }
            }
            .frame(width: 110, height: 110)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // The confidence word, not the raw score: PRD §16 keeps the model's
            // number internal.
            Text(entry.match.confidence.title, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}

private struct SectionView<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title, bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Titles

extension ItemStatus {
    var title: LocalizedStringKey {
        switch self {
        case .pending: "wardrobe.detail.illustration.pending"
        case .processing: "wardrobe.detail.illustration.processing"
        case .ready: "wardrobe.detail.illustration.ready"
        case .failed: "wardrobe.detail.illustration.failed"
        }
    }
}

extension ItemMatch.Confidence {
    var title: LocalizedStringKey {
        switch self {
        case .likely: "wardrobe.detail.similar.likely"
        case .uncertain: "wardrobe.detail.similar.uncertain"
        }
    }
}
