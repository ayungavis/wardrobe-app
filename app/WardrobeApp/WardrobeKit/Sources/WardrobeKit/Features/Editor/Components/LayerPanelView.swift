import DesignSystem
import SwiftUI

/// The layer panel (FR-090).
///
/// An ordered semantic list, which §19 asks for by name: every layer reachable,
/// every operation a button. It is also the only way back to a locked layer —
/// the canvas stops answering its gestures (FR-086) — so selection lives here
/// rather than only on the canvas.
struct LayerPanelView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: EditorViewModel

    /// Top of the stack first. `EditorDocument.layers` is ordered bottom to
    /// top, and a list that reads the other way round would have the front
    /// layer at the bottom of the screen.
    private var rows: [(offset: Int, element: EditorLayer)] {
        Array(viewModel.document.layers.enumerated()).reversed()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("editor.layers.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbar }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .presentationBackground(AppColor.mediaSurface)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.document.layers.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("editor.layers.empty.title", bundle: .module)
                } icon: {
                    Image(systemName: "square.3.layers.3d")
                }
            } description: {
                Text("editor.layers.empty.message", bundle: .module)
            }
        } else {
            List {
                ForEach(rows, id: \.element.id) { depth, layer in
                    row(layer, depth: depth)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ layer: EditorLayer, depth: Int) -> some View {
        LayerRowView(
            layer: layer,
            photo: viewModel.croppedPreviewImage,
            isSelected: viewModel.selectedLayerID == layer.id,
            depth: depth,
            layerCount: viewModel.document.layers.count,
            onSelect: { viewModel.select(layer.id) },
            onToggleLock: { viewModel.setLock(!layer.isLocked, ofLayer: layer.id) },
            onMove: { viewModel.moveLayer(id: layer.id, $0) },
            onStep: { viewModel.step($0, layerID: layer.id) },
            onDuplicate: { viewModel.duplicateLayer(id: layer.id) },
            onDelete: { viewModel.removeLayer(id: layer.id) }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Text("editor.layers.count \(viewModel.document.layers.count)", bundle: .module)
                .font(AppFont.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppColor.onMedia.opacity(0.64))
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: dismiss.callAsFunction) {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
            }
        }
    }
}
