import Foundation

// MARK: - Undo / redo (FR-088)

public extension EditorViewModel {
    var didFailToPersistDraft: Bool {
        activeRepository.didFailToPersist
    }

    func viewDisappeared() {
        flushTask = Task { await flush() }
    }

    func flush() async {
        await activeRepository.flush()
    }

    var canUndo: Bool {
        history.canUndo
    }

    var recentUndoSteps: [EditorDocument] {
        Array(history.undoStack.suffix(DocumentHistory.uploadedStepLimit))
    }

    var canRedo: Bool {
        history.canRedo
    }

    func undo() {
        restore(history.undo(current: document))
    }

    func redo() {
        restore(history.redo(current: document))
    }

    private func restore(_ snapshot: EditorDocument?) {
        guard let snapshot else { return }

        let previousCrops = document.photoCrops
        document = snapshot
        if let selectedLayerID, document.layer(id: selectedLayerID) == nil {
            self.selectedLayerID = nil
        }
        if document.photoCrops != previousCrops {
            updateCroppedPreviews()
        }
        write(document)
    }
}
