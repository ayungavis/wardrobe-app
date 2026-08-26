import DesignSystem
import SwiftUI

public struct WardrobeItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WardrobeItemDetailViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var isRegeneratePresented = false
    @State private var isEditing: Bool = false
    @State private var isIllustrationPresented = false
    private static let pinchToOpen: CGFloat = 1.3
    @Namespace private var illustrationNamespace

    @State private var editableName: String = ""
    @State private var editableDescription: String = ""

    public init(viewModel: WardrobeItemDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let item = viewModel.item {
                        hero(for: item)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.xl)

                        Text("wardrobe.wearCount.used \(viewModel.wearCount)", bundle: .module)
                            .font(AppFont.title)
                            .fontWeight(.black)
                            .stroke(color: AppColor.onMedia, width: 3)
                            .padding(.top, Spacing.lg)
                            .zIndex(2)

                        EditableInfoCardView(
                            isEditing: isEditing,
                            name: $editableName,
                            description: $editableDescription,
                            lastWornAt: viewModel.lastWornAt,
                            wears: viewModel.wears
                        )
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if isEditing {
                                        viewModel.updateItem(name: editableName, description: editableDescription)
                                    }
                                    isEditing.toggle()
                                }
                            } label: {
                                Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                                    .font(AppFont.title)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(width: 50, height: 50)
                                    .background(Circle().fill(AppColor.background))
                                    .appShadow(.card)
                            }
                            .padding(.top, Spacing.xs)
                            .padding(.trailing, Spacing.sm)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)

                        illustrationRow(item)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.lg)

                        timeline
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.lg)

                        similar
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.lg)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .appBackgroundOnly()
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(AppFont.caption.weight(.bold))
                            .foregroundStyle(AppColor.destructive)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular, in: .circle)
                            .appShadow(.card)
                    }
                }
            }
        #if os(iOS)
            .fullScreenCover(isPresented: $isIllustrationPresented) {
                if let item = viewModel.item, let data = viewModel.thumbnailData(for: item) {
                    IllustrationDetailView(data: data)
                        .navigationTransition(.zoom(sourceID: "illustration", in: illustrationNamespace))
                }
            }
        #endif
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
                    dismiss()
                }
            }
            .confirmationDialog(
                Text("wardrobe.detail.delete.title", bundle: .module),
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) { viewModel.delete() } label: { Text("wardrobe.detail.delete.action", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("common.cancel", bundle: .module) }
            } message: {
                Text("wardrobe.detail.delete.message", bundle: .module)
            }
            .sheet(isPresented: $isRegeneratePresented) {
                RegenerateIllustrationView(
                    cutout: viewModel.cutoutData(),
                    original: viewModel.originalPhotoData()
                ) { note in
                    viewModel.regenerateIllustration(note: note)
                    isRegeneratePresented = false
                }
                .presentationDetents([.fraction(0.72), .large])
            }
            .confirmationDialog(
                Text("wardrobe.detail.merge.title", bundle: .module),
                isPresented: Binding(
                    get: { viewModel.pendingMerge != nil },
                    set: {
                        if !$0 {
                            viewModel.cancelMerge()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    viewModel.confirmMerge()
                } label: {
                    Text("wardrobe.detail.merge.action", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("common.cancel", bundle: .module) }
            } message: {
                Text("wardrobe.detail.merge.message", bundle: .module)
            }
    }

    @ViewBuilder
    private func hero(for item: WardrobeItem) -> some View {
        let data = viewModel.thumbnailData(for: item)

        if let data {
            Button {
                isIllustrationPresented = true
            } label: {
                HeroView(data: data, isEditing: isEditing)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { isIllustrationPresented = true })
            .simultaneousGesture(
                MagnifyGesture().onChanged { value in
                    if value.magnification > Self.pinchToOpen {
                        isIllustrationPresented = true
                    }
                }
            )
            #if os(iOS)
            .matchedTransitionSource(id: "illustration", in: illustrationNamespace)
            #endif
            .accessibilityLabel(Text("wardrobe.detail.illustration.open", bundle: .module))
        } else {
            HeroView(data: nil, isEditing: isEditing)
        }
    }

    private func illustrationRow(_ item: WardrobeItem) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(item.status.title, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            Spacer()

            Button {
                isRegeneratePresented = true
            } label: {
                Text("wardrobe.detail.regenerate.action", bundle: .module)
                    .font(AppFont.caption.bold())
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRegenerating)
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
                                data: viewModel.thumbnailData(for: entry.item),
                                onMerge: { viewModel.requestMerge(entry) }
                            )
                        }
                    }
                }
            }
        }
    }
}

extension ItemStatus {
    var title: LocalizedStringKey {
        switch self {
        case .undrawn: "wardrobe.detail.illustration.undrawn"
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
