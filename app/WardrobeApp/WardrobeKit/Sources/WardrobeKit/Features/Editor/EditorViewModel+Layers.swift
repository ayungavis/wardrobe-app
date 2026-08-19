import Foundation

// MARK: - Layer panel (FR-090 reorder, FR-086 lock, §19 discrete adjustment)

public extension EditorViewModel {
    func moveLayer(id: UUID, _ move: EditorDocument.LayerMove) {
        document.moveLayer(id: id, move)
        persistDocument()
    }

    func reorderLayers(topFirstIDs ids: [UUID]) {
        let before = document.layers.map(\.id)
        document.reorderLayers(topFirstIDs: ids)
        guard document.layers.map(\.id) != before else { return }

        persistDocument()
    }

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

    internal func step(_ step: LayerStep, layerID: UUID) {
        guard let layer = document.layer(id: layerID) else { return }
        commitTransform(layerID: layerID, to: LayerStep.apply(step, to: layer.transform))
    }
}
