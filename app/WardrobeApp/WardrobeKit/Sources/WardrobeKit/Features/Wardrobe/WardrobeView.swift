//import DesignSystem
//import SwiftUI
//
//public struct WardrobeView: View {
//    public init() {}
//
//    public var body: some View {
//        NavigationStack {
//            // PRD §17: empty state explains that completing the first
//            // challenge creates wardrobe items.
//            ContentUnavailableView {
//                Label {
//                    Text("wardrobe.empty.title", bundle: .module)
//                } icon: {
//                    Image(systemName: "tshirt")
//                }
//            } description: {
//                Text("wardrobe.empty.message", bundle: .module)
//            }
//            .navigationTitle(Text("tab.wardrobe", bundle: .module))
//        }
//    }
//}
//
//#Preview {
//    WardrobeView()
//}
import SwiftUI
import PhotosUI

struct WardrobeView: View {
    @StateObject private var viewModel = WardrobeViewModel()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var filter: CategoryFilter = .all

    enum CategoryFilter: String, CaseIterable {
        case all = "All"
        case top = "Tops"
        case bottom = "Bottoms"
    }

    private var filteredItems: [ClothingItem] {
        switch filter {
        case .all: return viewModel.items
        case .top: return viewModel.items.filter { $0.category == "top" }
        case .bottom: return viewModel.items.filter { $0.category == "bottom" }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 20,
                matching: .images
            ) {
                if viewModel.isScanning {
                    Text("Processing… \(Int(viewModel.scanProgress * 100))%")
                } else {
                    Text("Add Outfit Photos")
                }
            }
            .disabled(viewModel.isScanning)
            .buttonStyle(.borderedProminent)
            .padding()
            .onChange(of: selectedPhotos) { _, newItems in
                Task {
                    guard !newItems.isEmpty else { return }

                    var entries: [(id: String, image: UIImage)] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            let id = "\(data.hashValue)"
                            entries.append((id: id, image: uiImage))
                        }
                    }

                    await viewModel.processSelectedPhotos(entries)
                }
            }

            Picker("Filter", selection: $filter) {
                ForEach(CategoryFilter.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems, id: \.id) { item in
                        VStack {
                            if let uiImage = UIImage(contentsOfFile: item.croppedThumbnailPath) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 150)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gray.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 150)
                            }

                            Text(item.category.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
    }
}
