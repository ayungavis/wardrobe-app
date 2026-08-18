import DesignSystem
import SwiftUI

/// Story-style editor: full-bleed photo on black, tool rail on the right,
/// send arrow bottom-right (Mobbin ref: Instagram "Creating a story").
public struct EditorView<ReviewDrawer: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EditorViewModel
    @State private var canvasSize: CGSize = .zero
    @State private var isDiscardConfirmPresented = false

    private let onDiscard: () -> Void
    private let onComplete: () -> Void
    /// The item-review drawer, supplied by the capture flow that owns the scan
    /// results — the editor only decides where it sits. Generic rather than
    /// `AnyView`: type erasure here would cost SwiftUI its diffing for nothing.
    private let reviewDrawer: ReviewDrawer

    public init(
        viewModel: EditorViewModel,
        onDiscard: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        @ViewBuilder reviewDrawer: () -> ReviewDrawer
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDiscard = onDiscard
        self.onComplete = onComplete
        self.reviewDrawer = reviewDrawer()
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            AppColor.mediaBackground.ignoresSafeArea()
            content
        }
        .environment(\.colorScheme, .dark)
        .task { viewModel.onAppear() }
        .sheet(isPresented: $viewModel.isExportPresented) {
            ExportSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isStickerPickerPresented) {
            StickerPickerView(recentIDs: viewModel.recentStickerIDs) { viewModel.addSticker($0) }
                // Half height so the canvas stays in view, and draggable to
                // full for browsing the whole catalogue.
                .presentationDetents([.fraction(0.48), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(30)
                .presentationBackground(AppColor.mediaSurface)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $viewModel.isBackgroundPickerPresented) {
            BackgroundPickerView(
                selected: viewModel.document.background,
                onPick: viewModel.setBackground
            )
            // Short enough that the canvas stays readable behind it, and opaque
            // rather than material so the swatches are judged against the
            // background they will actually produce.
            .presentationDetents([.height(230)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
            .presentationBackground(AppColor.mediaSurface)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            Text("editor.discard.title", bundle: .module),
            isPresented: $isDiscardConfirmPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDiscard) {
                Text("editor.discard.action", bundle: .module)
            }
            Button(action: dismiss.callAsFunction) {
                // FR-017: the draft survives; resume comes back here.
                Text("editor.discard.keep", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text("editor.discard.message", bundle: .module)
        }
        .alert(
            Text("common.errorTitle", bundle: .module),
            isPresented: Binding(
                get: { viewModel.alertError != nil },
                set: {
                    if !$0 {
                        viewModel.alertError = nil
                    }
                }
            )
        ) {
            Button(role: .cancel) {} label: { Text("common.ok", bundle: .module) }
        } message: {
            Text(viewModel.alertError?.userMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.originalData {
        case .idle, .loading:
            ProgressView()
                .tint(AppColor.onMedia)
        case let .failed(error):
            EditorLoadFailedView(error: error, onRetry: viewModel.load)
        case .loaded:
            if case let .crop(spec) = viewModel.activeTool {
                CropStageView(
                    image: viewModel.previewImage,
                    spec: spec,
                    onChange: { viewModel.updateWorking(crop: $0) },
                    onCancel: viewModel.cancelTool,
                    onDone: viewModel.commitTool
                )
            } else {
                canvasStage
            }
        }
    }

    private var canvasStage: some View {
        ZStack {
            EditorCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                // The canvas is the unit everything is measured against — text
                // sizes, layer positions, the exported frame. Letting the
                // keyboard shrink it would rescale the whole document every
                // time the composer opened.
                .ignoresSafeArea(.keyboard)

            if viewModel.activeTool == nil {
                VStack {
                    Spacer()
                    reviewDrawer
                        .padding(.bottom, 96) // clears the Save/Share/✓ bar
                }

                EditorControlsView(
                    isSaving: viewModel.isSaving,
                    didSave: viewModel.didSaveToPhotos,
                    onClose: { isDiscardConfirmPresented = true },
                    onText: { viewModel.beginNewText() },
                    onSticker: { viewModel.isStickerPickerPresented = true },
                    onCrop: viewModel.beginCrop,
                    onBackground: { viewModel.isBackgroundPickerPresented = true },
                    onSave: viewModel.saveDirectly,
                    onShare: viewModel.beginExport,
                    onComplete: onComplete
                )
            }

            if case let .text(working, isNew) = viewModel.activeTool {
                TextComposerView(
                    working: working,
                    isExisting: !isNew,
                    canvasSize: canvasSize,
                    onUpdate: { viewModel.updateWorking(text: $0) },
                    onDelete: viewModel.removeWorkingText,
                    onCancel: viewModel.cancelTool,
                    onDone: viewModel.commitTool
                )
            }
        }
    }
}
