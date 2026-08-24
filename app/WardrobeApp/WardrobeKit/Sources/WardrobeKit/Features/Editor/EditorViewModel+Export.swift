import Foundation

// MARK: - Export / save / share (FR-031/032 — independent of completion)

public extension EditorViewModel {
    var isExporting: Bool {
        if case .loading = exportState {
            return true
        }
        return false
    }

    func beginExport() {
        guard case let .loaded(originals) = originals else { return }
        exportTask?.cancel()
        exportState = .loading
        isExportPresented = true

        let document = document
        exportTask = Task {
            do {
                let start = ContinuousClock.now
                let photo = try await ExportService.render(originals: originals, document: document)
                try Task.checkCancellation()
                Log.ui.info(
                    "Export finished in \((ContinuousClock.now - start).ms, privacy: .public)ms"
                )
                exportState = .loaded(ExportedPhoto(data: photo))
            } catch is CancellationError {
            } catch {
                Log.report(error)
                exportState = .failed(.exportFailed)
            }
        }
    }

    func saveDirectly() {
        guard case let .loaded(originals) = originals, saveState == .idle else { return }
        saveTask?.cancel()
        saveState = .saving

        let document = document
        saveTask = Task {
            do {
                let photo = try await ExportService.render(originals: originals, document: document)
                try Task.checkCancellation()
                try await librarySaver.save(photo)
                saveState = .saved
            } catch is CancellationError {
                saveState = .idle
            } catch {
                Log.report(error)
                saveState = .idle
                alertError = error as? AppError ?? .photoSaveFailed
            }
        }
    }
}
