import Foundation

// MARK: - Layer panel (FR-090 reorder, FR-086 lock, §19 discrete adjustment)

/// Its own file only because `EditorViewModel.swift` reached the type-body
/// limit. Still part of the type — this and `EditorViewModel+Export.swift`
/// are why `document`, `selectedLayerID`, and `persistDocument()` are
/// internal rather than private: `private` is file-scoped in Swift.
public extension EditorViewModel {
    func moveLayer(id: UUID, _ move: EditorDocument.LayerMove) {
        document.moveLayer(id: id, move)
        persistDocument()
    }

    /// The panel's drag, as an order rather than a move — see
    /// `reorderLayers(topFirstIDs:)` for why that distinction is the fix and
    /// not a preference.
    ///
    /// Selection is deliberately left alone: with an order there is no "the
    /// layer that moved" to select, and reaching for one is what put the
    /// selection on an untouched layer while the delta version was misfiring.
    func reorderLayers(topFirstIDs ids: [UUID]) {
        let before = document.layers.map(\.id)
        document.reorderLayers(topFirstIDs: ids)
        guard document.layers.map(\.id) != before else { return }

        persistDocument()
    }

    /// Locking selects, because the panel is the only way back to a locked
    /// layer — the canvas ignores its gestures (FR-086).
    func setLock(_ isLocked: Bool, ofLayer id: UUID) {
        document.setLock(isLocked, ofLayer: id)
        selectedLayerID = id
        persistDocument()
    }

    func duplicateLayer(id: UUID) {
        guard let copy = document.duplicateLayer(id: id) else { return }
        selectedLayerID = copy
        persistDocument()
    }

    /// §19's discrete adjustment. Routed through `commitTransform` so it
    /// inherits the locked-layer refusal and the scale bound rather than
    /// repeating them.
    internal func step(_ step: LayerStep, layerID: UUID) {
        guard let layer = document.layer(id: layerID) else { return }
        commitTransform(layerID: layerID, to: LayerStep.apply(step, to: layer.transform))
    }
}
