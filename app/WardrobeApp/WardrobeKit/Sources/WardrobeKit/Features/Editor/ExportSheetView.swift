import DesignSystem
import SwiftUI

/// FR-031: Save and Share are independent of completion.
struct ExportSheetView: View {
    let viewModel: EditorViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.exportState {
                case .idle, .loading:
                    ProgressView()
                case let .failed(error):
                    ContentUnavailableView {
                        Label {
                            Text("common.errorTitle", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                        }
                    } description: {
                        Text(error.userMessage)
                    } actions: {
                        Button {
                            viewModel.beginExport()
                        } label: {
                            Text("common.retry", bundle: .module)
                        }
                    }
                case let .loaded(photo):
                    VStack(spacing: Spacing.xl) {
                        DownsampledPhotoView(data: photo.data)
                            .clipShape(.rect(cornerRadius: 12))

                        // Saving lives on the editor's bottom bar — one path.
                        ShareLink(
                            item: photo,
                            preview: SharePreview(String(localized: "editor.export.title", bundle: .module))
                        )
                        .frame(minHeight: 44)
                    }
                    .padding(Spacing.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .navigationTitle(Text("editor.export.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
    }
}
