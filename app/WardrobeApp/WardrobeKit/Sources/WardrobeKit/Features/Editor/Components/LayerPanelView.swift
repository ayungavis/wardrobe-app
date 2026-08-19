import DesignSystem
import SwiftUI

struct LayerPanelView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: EditorViewModel

    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif

    @State private var rows: [EditorLayer] = []

    private var isReordering: Bool {
        #if os(iOS)
            editMode == .active
        #else
            false
        #endif
    }

    private func depth(of layer: EditorLayer) -> Int {
        guard let row = rows.firstIndex(where: { $0.id == layer.id }) else { return 0 }
        return rows.count - 1 - row
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
        .onAppear { rows = viewModel.document.layers.reversed() }
        .onChange(of: viewModel.document.layers) { _, layers in
            rows = layers.reversed()
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
                ForEach(rows) { layer in
                    row(layer)
                }
                .onMove { source, destination in
                    EditorHaptics.selection.play()
                    rows.move(fromOffsets: source, toOffset: destination)
                    viewModel.reorderLayers(topFirstIDs: rows.map(\.id))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
                .environment(\.editMode, $editMode)
            #endif
        }
    }

    private func row(_ layer: EditorLayer) -> some View {
        LayerRowView(
            layer: layer,
            photo: viewModel.preview(forPhoto:),
            isSelected: viewModel.selectedLayerID == layer.id,
            depth: depth(of: layer),
            layerCount: viewModel.document.layers.count,
            isReordering: isReordering,
            isChallengePhoto: !viewModel.canRemove(layerID: layer.id),
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
            Text(viewModel.document.layers.count, format: .number)
                .font(AppFont.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppColor.onMedia.opacity(0.64))
                .accessibilityLabel(Text(
                    "editor.layers.count \(viewModel.document.layers.count)", bundle: .module
                ))
        }

        ToolbarItem(placement: .primaryAction) {
            reorderToggle
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: dismiss.callAsFunction) {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
            }
        }
    }

    private var reorderToggle: some View {
        Button(action: toggleReordering) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(isReordering ? AppColor.accent : AppColor.onMedia)
        }
        .accessibilityLabel(Text("editor.layers.reorder", bundle: .module))
        .accessibilityAddTraits(isReordering ? [.isSelected] : [])
        .accessibilityIdentifier("editor.layers.reorderToggle")
    }

    private func toggleReordering() {
        #if os(iOS)
            editMode = isReordering ? .inactive : .active
        #endif
    }
}
