import DesignSystem
import PhotosUI
import SwiftUI

struct PhotoLibraryGridView: View {
    @Environment(\.dismiss) private var dismiss

    let access: PhotoLibraryAccess
    let assets: [PhotoAsset]
    let thumbnail: @Sendable (String) async -> CGImage?
    let onPick: (String) -> Void
    let onPickData: (Data) -> Void
    let onLoadMore: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if access.canBrowse {
                    grid
                } else {
                    PhotoLibraryDeniedView(onPickData: onPickData, onDismiss: dismiss.callAsFunction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.mediaBackground)
            .navigationTitle(Text("capture.gallery.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                }
        }
        .environment(\.colorScheme, .dark)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(assets) { asset in
                    Button {
                        onPick(asset.id)
                    } label: {
                        PhotoGridCellView(assetID: asset.id, thumbnail: thumbnail)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if asset == assets.last {
                            onLoadMore()
                        }
                    }
                }
            }
        }
    }
}

private struct PhotoGridCellView: View {
    let assetID: String
    let thumbnail: @Sendable (String) async -> CGImage?

    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    AppColor.onMedia.opacity(0.08)
                }
            }
            .clipped()
            .task(id: assetID) {
                image = await thumbnail(assetID)
            }
    }
}

private struct PhotoLibraryDeniedView: View {
    @Environment(\.openURL) private var openURL

    let onPickData: (Data) -> Void
    let onDismiss: () -> Void

    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.onMedia.opacity(0.6))

            Text("capture.gallery.denied.title", bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.onMedia)
                .multilineTextAlignment(.center)

            Text("capture.gallery.denied.message", bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.onMedia.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()

            #if os(iOS)
                PrimaryButtonView(Text("capture.denied.openSettings", bundle: .module)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            #endif

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Text("capture.gallery.useSystemPicker", bundle: .module)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(Spacing.xl)
        .onChange(of: pickedItem) { _, newItem in
            loadPickedItem(newItem)
        }
    }

    private func loadPickedItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { pickedItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                onPickData(data)
                onDismiss()
            } catch {
                Log.report(error, logger: Log.ui)
            }
        }
    }
}
