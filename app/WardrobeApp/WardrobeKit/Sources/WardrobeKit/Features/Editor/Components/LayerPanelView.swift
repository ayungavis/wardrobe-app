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

    // A real binding, not `.constant(...)`: the list manages its own edit
    // state while a drag is in flight, and a binding it cannot write to leaves
    // it reconciling against something it does not own.
    //
    // Guarded because `EditMode` does not exist on macOS, and this package
    // builds for macOS so `swift test` runs without a simulator.
    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif

    /// The list's own source of truth, top of the stack first — deliberately
    /// not a computed read of the document.
    ///
    /// A drag moves this first and commits second. Re-deriving it from the
    /// document instead means the commit changes the list's data while the
    /// list's own drag is still in flight, which is what made one drag land as
    /// two: rows drawn twice, and the same move applied twice.
    @State private var rows: [EditorLayer] = []

    private var isReordering: Bool {
        #if os(iOS)
            editMode == .active
        #else
            false
        #endif
    }

    /// How far up the stack a layer sits, counted from the bottom. Read off the
    /// array the list actually draws, so a row can never label itself from a
    /// different order than the one it is in.
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
            // Everything that is not a drag — delete, duplicate, the menu's four
            // reorder items — arrives here. After a drag this assigns the value
            // already held, so SwiftUI sees no change and nothing rebuilds.
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
            // A mode you turn on, not a permanent state: the system's reorder
            // control and the row's own buttons occupy the same row, and pinning
            // edit mode leaves the row half-dead.
            #if os(iOS)
                .environment(\.editMode, $editMode)
            #endif
        }
    }

    private func row(_ layer: EditorLayer) -> some View {
        LayerRowView(
            layer: layer,
            photo: viewModel.croppedPreviewImage,
            isSelected: viewModel.selectedLayerID == layer.id,
            depth: depth(of: layer),
            layerCount: viewModel.document.layers.count,
            isReordering: isReordering,
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
            // The number alone — spelled out it collides with the inline
            // title. VoiceOver still gets the whole phrase, since a bare digit
            // read aloud means nothing.
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
