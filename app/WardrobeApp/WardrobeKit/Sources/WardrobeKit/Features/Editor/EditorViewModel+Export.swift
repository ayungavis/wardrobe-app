import Foundation

// MARK: - Export / save / share (FR-031/032 — independent of completion)

// Its own file only because `EditorViewModel.swift` reached the file-length
// limit. The three pieces of state written here are `internal(set)` for the
// same reason — this extension is still part of the type, just not part of
// the file.

public extension EditorViewModel {
    func beginExport() {
        guard case let .loaded(data) = originalData else { return }
        exportTask?.cancel()
        exportState = .loading
        didSaveToPhotos = false
        isExportPresented = true

        let document = document
        exportTask = Task {
            do {
                let start = ContinuousClock.now
                let photo = try ExportService.render(original: data, document: document)
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

    func saveToPhotos() {
        guard case let .loaded(photo) = exportState else { return }
        saveTask = Task {
            do {
                try await librarySaver.save(photo.data)
                didSaveToPhotos = true
            } catch {
                Log.report(error)
                alertError = .photoSaveFailed
            }
        }
    }

    /// Save-pill path: render + save to the library in one step, no sheet.
    func saveDirectly() {
        guard case let .loaded(data) = originalData, !isSaving, !didSaveToPhotos else { return }
        isSaving = true

        let document = document
        saveTask = Task {
            defer { isSaving = false }
            do {
                let photo = try ExportService.render(original: data, document: document)
                try Task.checkCancellation()
                try await librarySaver.save(photo)
                didSaveToPhotos = true
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                alertError = .photoSaveFailed
            }
        }
    }
}
