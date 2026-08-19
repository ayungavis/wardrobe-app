import DesignSystem
import SwiftUI

/// Story-style editor: full-bleed photo on black, tool rail on the right,
/// send arrow bottom-right (Mobbin ref: Instagram "Creating a story").
public struct EditorView<ReviewDrawer: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var viewModel: EditorViewModel
    @State private var canvasSize: CGSize = .zero
    @State private var isDiscardConfirmPresented = false
    /// Seeded from `didResumeDraft` on appear so dismissing it sticks for the
    /// life of this editor session.
    @State private var isRestoredNoticeVisible = false

    private let isCompleting: Bool
    private let didResumeDraft: Bool
    /// Nil when there is no photo to reframe. Supplied by the capture flow,
    /// which is the only thing that knows which photo this is.
    private let makeCropViewModel: (String) -> CropViewModel
    private let onDiscard: () -> Void
    private let onComplete: () -> Void
    /// The item-review drawer, supplied by the capture flow that owns the scan
    /// results — the editor only decides where it sits. Generic rather than
    /// `AnyView`: type erasure here would cost SwiftUI its diffing for nothing.
    private let reviewDrawer: ReviewDrawer

    public init(
        viewModel: EditorViewModel,
        isCompleting: Bool,
        didResumeDraft: Bool,
        makeCropViewModel: @escaping (String) -> CropViewModel,
        onDiscard: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        @ViewBuilder reviewDrawer: () -> ReviewDrawer
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.isCompleting = isCompleting
        self.didResumeDraft = didResumeDraft
        self.makeCropViewModel = makeCropViewModel
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
        // Value-based rather than a call in a button: an export and a save
        // finish long after the tap, and this is the value that says so.
        .sensoryFeedback(.success, trigger: viewModel.didSaveToPhotos) { $1 }
        .sensoryFeedback(.error, trigger: viewModel.alertError) { $1 != nil }
        .task(id: didResumeDraft) { await showRestoredNotice() }
        // Leaving the editor is the other moment a coalesced write has to
        // be made to land.
        .onDisappear { Task { await viewModel.flush() } }
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
        .sheet(isPresented: $viewModel.isLayerPanelPresented) {
            LayerPanelView(viewModel: viewModel)
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
        switch viewModel.originals {
        case .idle, .loading:
            ProgressView()
                .tint(AppColor.onMedia)
        case let .failed(error):
            EditorLoadFailedView(error: error, onRetry: viewModel.load)
        case .loaded:
            if case let .crop(layerID) = viewModel.activeTool, let photoID = viewModel.croppingPhotoID {
                // The same screen the capture flow uses, not a second crop tool
                // that could drift from it — only the meaning of leaving differs.
                CropView(
                    viewModel: makeCropViewModel(photoID),
                    exit: .cancel,
                    onExit: viewModel.cancelTool,
                    onUseCrop: { viewModel.commitCrop($0, ofLayer: layerID) }
                )
            } else {
                canvasStage
            }
        }
    }

    /// News about the past, so it leaves on its own — long enough to read the
    /// longer of the two translations, and no longer.
    ///
    /// Not while VoiceOver is running: content that vanishes after four seconds
    /// is content that may never have finished being spoken. It is a small
    /// element in the top corner blocking nothing, so letting it sit until the
    /// editor closes costs nothing either.
    private func showRestoredNotice() async {
        guard didResumeDraft else { return }
        withAnimation(reduceMotion ? nil : .snappy) { isRestoredNoticeVisible = true }
        guard !voiceOverEnabled else { return }

        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .snappy) { isRestoredNoticeVisible = false }
    }

    /// A failure outranks the restoration notice: one is bad news still
    /// happening, the other a note about the past.
    private var draftBannerKind: DraftBannerView.Kind? {
        if viewModel.didFailToPersistDraft {
            return .writeFailed
        }
        return isRestoredNoticeVisible ? .restored : nil
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

                if let banner = draftBannerKind {
                    VStack {
                        HStack {
                            DraftBannerView(kind: banner)
                                .transition(.opacity)
                            Spacer(minLength: Spacing.xxl)
                        }
                        // Clears the close button it sits under.
                        .padding(.top, 60)
                        Spacer()
                    }
                    .padding(Spacing.lg)
                }

                EditorControlsView(
                    isSaving: viewModel.isSaving,
                    didSave: viewModel.didSaveToPhotos,
                    isExporting: viewModel.isExporting,
                    isCompleting: isCompleting,
                    onClose: { isDiscardConfirmPresented = true },
                    canUndo: viewModel.canUndo,
                    canRedo: viewModel.canRedo,
                    onUndo: viewModel.undo,
                    onRedo: viewModel.redo,
                    onText: { viewModel.beginNewText() },
                    onSticker: { viewModel.isStickerPickerPresented = true },
                    onPickPhoto: viewModel.addPhoto,
                    onBackground: { viewModel.isBackgroundPickerPresented = true },
                    onDrawing: viewModel.beginDrawing,
                    onLayers: { viewModel.isLayerPanelPresented = true },
                    onSave: viewModel.saveDirectly,
                    onShare: viewModel.beginExport,
                    onComplete: onComplete
                )
            }

            if case let .drawing(session) = viewModel.activeTool {
                VStack {
                    Spacer()
                    DrawingToolbarView(
                        pen: viewModel.pen,
                        canClear: !session.isEmpty,
                        onSelectColor: { viewModel.setPen(color: $0) },
                        onSelectWidth: { viewModel.setPen(width: $0) },
                        onToggleEraser: viewModel.toggleEraser,
                        onClear: viewModel.clearDrawing,
                        onCancel: viewModel.cancelTool,
                        onDone: { viewModel.finishDrawing(canvasSize: canvasSize) }
                    )
                    .padding(.bottom, Spacing.lg)
                }
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
