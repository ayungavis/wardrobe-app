import Foundation

// MARK: - Undo / redo (FR-088)

/// Its own file only because `EditorViewModel.swift` reached the type-body
/// limit — `history`, `write(_:)`, and `updateCroppedPreview()` are internal
/// for the same reason, since `private` is file-scoped in Swift.
public extension EditorViewModel {
    var canUndo: Bool {
        history.canUndo
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

    /// Deliberately not through `persistDocument`, which would make undo record
    /// itself as an edit.
    ///
    /// Two couplings the document cannot express on its own: the cropped
    /// preview is stored rather than computed, so stepping across a crop has to
    /// re-derive it; and a selection can outlive the layer it names once a
    /// delete is undone in the other direction.
    private func restore(_ snapshot: EditorDocument?) {
        guard let snapshot else { return }

        let previousCrop = document.photoCrop
        document = snapshot
        if let selectedLayerID, document.layer(id: selectedLayerID) == nil {
            self.selectedLayerID = nil
        }
        if document.photoCrop != previousCrop {
            updateCroppedPreview()
        }
        write(document)
    }
}
