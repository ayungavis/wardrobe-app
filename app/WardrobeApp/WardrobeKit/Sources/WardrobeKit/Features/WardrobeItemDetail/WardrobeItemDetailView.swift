import DesignSystem
import SwiftUI

/// One garment: what it looks like, how often it has been worn, and what else in
/// the wardrobe resembles it (PRD FR-036).
///
/// Name, colour, and garment type are not shown because they do not exist yet
/// (PRD §13.4). Empty fields promising future data would be worse than their
/// absence.
public struct WardrobeItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WardrobeItemDetailViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditing: Bool = false
        
        @State private var editableName: String = ""
        @State private var editableDescription: String = ""

    /// Called after the row is gone, so the grid behind can reload.
    private let onDeleted: () -> Void

    public init(viewModel: WardrobeItemDetailViewModel, onDeleted: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDeleted = onDeleted
    }

//    public var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: Spacing.xl) {
//                if let item = viewModel.item {
//                    HeroView(data: viewModel.thumbnailData(for: item))
//                    UsageSummaryView(
//                        name: item.name,
//                        category: item.category,
//                        status: item.status,
//                        wearCount: viewModel.wearCount,
//                        firstWornAt: viewModel.firstWornAt,
//                        lastWornAt: viewModel.lastWornAt
//                    )
//                    timeline
//                    similar
//                    deleteButton
//                }
//            }
//            .padding(Spacing.lg)
//        }
//        .frame(maxWidth: .infinity)
//        .background(AppColor.background)
//        .navigationTitle(Text("wardrobe.detail.title", bundle: .module))
//        #if os(iOS)
//            .navigationBarTitleDisplayMode(.inline)
//        #endif
//            .task { viewModel.load() }
//            .onChange(of: viewModel.isDeleted) { _, deleted in
//                if deleted {
//                    onDeleted()
//                    dismiss()
//                }
//            }
//            .confirmationDialog(
//                Text("wardrobe.detail.delete.title", bundle: .module),
//                isPresented: $isDeleteConfirmationPresented,
//                titleVisibility: .visible
//            ) {
//                Button(role: .destructive) {
//                    viewModel.delete()
//                } label: {
//                    Text("wardrobe.detail.delete.action", bundle: .module)
//                }
//                Button(role: .cancel) {} label: {
//                    Text("common.cancel", bundle: .module)
//                }
//            } message: {
//                // FR-018.14: the consequence is stated before the red button,
//                // not discovered after it.
//                Text("wardrobe.detail.delete.message", bundle: .module)
//            }
//    }
    public var body: some View {
            ZStack {
                Image("appBG", bundle: .module)
                    .resizable()
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let item = viewModel.item {
                            
                            // 1. Hero Image
                            HeroView(
                                data: viewModel.thumbnailData(for: item),
                                isEditing: isEditing
                            )
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.xl)
                            
                            // 2. Wear Count
                            Text("\(viewModel.wearCount)x Used")
                                .font(AppFont.title) // Adjusted to use your design system
                                .fontWeight(.black)
                                .stroke(color: .white, width: 3)
                                .padding(.top, Spacing.lg)
                                .zIndex(2)
                                
                            
                            // 3. Receipt Card
                            EditableInfoCardView(
                                isEditing: isEditing,
                                name: $editableName,
                                description: $editableDescription,
                                lastWornAt: viewModel.lastWornAt
                            )
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.md)
                            
                            // 4. Delete Button (Edit Mode Only)
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
                            
                            // 5. Timeline & Similar Items (Only show in Read Mode to keep Edit UI clean)
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
            //.navigationTitle(isEditing ? "Edit Wear" : (viewModel.item?.category.title ?? "Detail"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if isEditing {
                                // Trigger the save when exiting edit mode
                                // IMPORTANT: Ensure your teammate adds this function to the ViewModel!
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
            // Sync local editable state when the item data arrives
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
                // Nothing cleared the matcher's threshold. That is information,
                // not a failure, so it is stated plainly.
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

//    private var deleteButton: some View {
//        Button(role: .destructive) {
//            isDeleteConfirmationPresented = true
//        } label: {
//            Text("wardrobe.detail.delete.action", bundle: .module)
//                .frame(maxWidth: .infinity)
//        }
//        .buttonStyle(.bordered)
//    }
//}

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
                // Replaces original UsageSummaryView with the paper asset
                Image("WardrobeItemDetail", bundle: .module)
                    .resizable()
                
                VStack(alignment: .leading, spacing: 16) {
                    // NAME
                    HStack {
                        Text("Name :").bold()
                        if isEditing {
                            TextField("Item Name", text: $name)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                                // Triggers end of editing on 'Return' key
                                .onSubmit {
                                    // optional: can trigger save here too if desired
                                }
                        } else {
                            Text(name)
                        }
                    }
                    
                   Divider()
                    
                    // LAST USED
                    HStack {
                        Text("Last Used :").bold()
                        Text(lastWornText(lastWornAt))
                    }
                    
                    Divider()
                    
                    // DESCRIPTION
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description :").bold()
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
        
        private func lastWornText(_ date: Date?) -> String {
            guard let date = date else { return "Never" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
    
//private struct UsageSummaryView: View {
//    let name: String
//    let category: GarmentCategory
//    let status: ItemStatus
//    let wearCount: Int
//    let firstWornAt: Date?
//    let lastWornAt: Date?
//
//    var body: some View {
//        SectionView(title: "wardrobe.detail.usage") {
//            VStack(spacing: Spacing.sm) {
//                row("wardrobe.detail.name") {
//                    Text("\(name)")
//                }
//                row("wardrobe.detail.category") {
//                    Text(category.title, bundle: .module)
//                }
//                row("wardrobe.detail.wearCount") {
//                    Text("\(wearCount)")
//                }
//                // Missing history is labelled, never filled with an invented
//                // date (FR-023).
//                row("wardrobe.detail.firstWorn") { date(firstWornAt) }
//                row("wardrobe.detail.lastWorn") { date(lastWornAt) }
//                row("wardrobe.detail.illustration") {
//                    Text(status.title, bundle: .module)
//                }
//            }
//        }
//    }

    @ViewBuilder
    private func date(_ value: Date?) -> some View {
        if let value {
            Text(value, format: .dateTime.day().month(.wide).year())
        } else {
            Text("wardrobe.detail.never", bundle: .module)
        }
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        LabeledContent {
            value()
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
        } label: {
            Text(title, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
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
