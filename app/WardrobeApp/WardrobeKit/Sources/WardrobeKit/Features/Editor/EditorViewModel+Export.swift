import Foundation

// MARK: - Export / save / share (FR-031/032 — independent of completion)

// Its own file only because `EditorViewModel.swift` reached the file-length
// limit. The three pieces of state written here are `internal(set)` for the
// same reason — this extension is still part of the type, just not part of
// the file.

public extension EditorViewModel {
    /// PRD §17: duplicate export actions have to be prevented, and the pill is
    /// where that is visible.
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
                // Ignore cancellation.
            } catch {
                Log.report(error)
                exportState = .failed(.exportFailed)
            }
        }
    }

    /// Save-pill path: render + save to the library in one step, no sheet.
    func saveDirectly() {
        guard case let .loaded(originals) = originals, !isSaving, !didSaveToPhotos else { return }
        isSaving = true

        let document = document
        saveTask = Task {
            defer { isSaving = false }
            do {
                let photo = try await ExportService.render(originals: originals, document: document)
                try Task.checkCancellation()
                try await librarySaver.save(photo)
                didSaveToPhotos = true
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                // Kept typed rather than flattened: a refused permission and a
                // failed write ask the user for different things.
                alertError = error as? AppError ?? .photoSaveFailed
            }
        }
    }
}
