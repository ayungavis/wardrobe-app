import DesignSystem
import SwiftUI

public struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var viewModel: EditorViewModel
    @State private var canvasSize: CGSize = .zero
    @State private var isDiscardConfirmPresented = false
    @State private var isRestoredNoticeVisible = false

    private let isCompleting: Bool
    private let didResumeDraft: Bool
    private let makeCropViewModel: (UUID) -> CropViewModel
    private let onDiscard: () -> Void
    private let onComplete: () -> Void

    public init(
        viewModel: EditorViewModel,
        isCompleting: Bool,
        didResumeDraft: Bool,
        makeCropViewModel: @escaping (UUID) -> CropViewModel,
        onDiscard: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.isCompleting = isCompleting
        self.didResumeDraft = didResumeDraft
        self.makeCropViewModel = makeCropViewModel
        self.onDiscard = onDiscard
        self.onComplete = onComplete
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            AppColor.mediaBackground.ignoresSafeArea()
            content
        }
        .environment(\.colorScheme, .dark)
        .task { viewModel.onAppear() }
        .sensoryFeedback(.success, trigger: viewModel.didSaveToPhotos) { $1 }
        .sensoryFeedback(.error, trigger: viewModel.alertError) { $1 != nil }
        .task(id: didResumeDraft) { await showRestoredNotice() }
        .onDisappear { viewModel.viewDisappeared() }
        .sheet(isPresented: $viewModel.isExportPresented) {
            ExportSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isStickerPickerPresented) {
            StickerPickerView(recentIDs: viewModel.recentStickerIDs) { viewModel.addSticker($0) }
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
                photo: viewModel.preview(forPhoto:),
                onPick: viewModel.setBackground,
                onPickPhoto: viewModel.setBackgroundPhoto
            )
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
            if case let .crop(target) = viewModel.activeTool, let photoID = viewModel.croppingPhotoID {
                CropView(
                    viewModel: makeCropViewModel(photoID),
                    exit: .cancel,
                    initialCrop: viewModel.croppingCrop,
                    aspectRatio: viewModel.croppingAspectRatio,
                    onExit: viewModel.cancelTool,
                    onUseCrop: { viewModel.commitCrop($0, for: target) }
                )
            } else {
                canvasStage
            }
        }
    }

    private func showRestoredNotice() async {
        guard didResumeDraft else { return }
        withAnimation(reduceMotion ? nil : .snappy) { isRestoredNoticeVisible = true }
        guard !voiceOverEnabled else { return }

        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .snappy) { isRestoredNoticeVisible = false }
    }

    private var draftBannerKind: DraftBannerView.Kind? {
        if viewModel.didFailToPersistDraft {
            return .writeFailed
        }
        return isRestoredNoticeVisible ? .restored : nil
    }

    private var canvasStage: some View {
        ZStack {
            EditorCanvasView(viewModel: viewModel, canvasSize: $canvasSize)
                .ignoresSafeArea(.keyboard)

            if viewModel.activeTool == nil {
                if let banner = draftBannerKind {
                    VStack {
                        HStack {
                            DraftBannerView(kind: banner)
                                .transition(.opacity)
                            Spacer(minLength: Spacing.xxl)
                        }
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
