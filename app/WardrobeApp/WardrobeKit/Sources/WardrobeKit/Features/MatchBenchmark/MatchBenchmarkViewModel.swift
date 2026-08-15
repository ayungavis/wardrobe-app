import Foundation
import Observation

/// Runs the real scan pipeline over photos the user has grouped by garment, and
/// scores the matcher against those groups.
///
/// It calls `GarmentScanService` — the same service the editor and the bulk scan
/// use — on purpose. A benchmark with its own copy of the pipeline would
/// eventually measure something the app does not do.
@MainActor
@Observable
final class MatchBenchmarkViewModel {
    struct Group: Identifiable, Equatable {
        let id: Int
        let photoCount: Int
        let garmentCount: Int
    }

    private(set) var groups: [Group] = []
    private(set) var isScanning = false
    private(set) var report: BenchmarkReport?

    private var samples: [BenchmarkSample] = []
    /// Assigned when the batch is picked, not when its scan finishes, so two
    /// quick taps cannot land in the same group.
    private var nextGroupIndex = 0

    private let scanner: GarmentScanService
    private let thumbnails: GarmentThumbnailRepository

    init(scanner: GarmentScanService, thumbnails: GarmentThumbnailRepository) {
        self.scanner = scanner
        self.thumbnails = thumbnails
    }

    /// One call per physical garment: every photo handed in here is the same
    /// piece of clothing.
    func add(photos: [Data]) {
        guard !photos.isEmpty else { return }
        let index = nextGroupIndex
        nextGroupIndex += 1
        isScanning = true
        report = nil

        // ponytail: segmentation runs on the main actor, same as the bulk scan.
        // A dev tool waiting a second per photo is not worth an actor hop.
        Task {
            defer { isScanning = false }
            let scanned = scan(photos, groupIndex: index)
            samples.append(contentsOf: scanned)
            groups.append(Group(id: index, photoCount: photos.count, garmentCount: scanned.count))
        }
    }

    func run() {
        report = MatchBenchmark.report(for: samples)
        if let formatted = report?.formatted {
            Log.ui.info("Benchmark\n\(formatted, privacy: .public)")
        }
    }

    func reset() {
        samples = []
        groups = []
        report = nil
        nextGroupIndex = 0
    }

    /// Cut-outs are written by the scan and immediately deleted: the benchmark
    /// needs the numbers, not the pictures, and nothing here belongs in the
    /// user's wardrobe.
    private func scan(_ photos: [Data], groupIndex: Int) -> [BenchmarkSample] {
        photos.flatMap { photo -> [BenchmarkSample] in
            do {
                return try scanner.scan(photo: photo).map { garment in
                    try? thumbnails.delete(file: garment.cutoutFile)
                    return BenchmarkSample(
                        id: garment.id,
                        groupIndex: groupIndex,
                        category: garment.category,
                        fingerprint: garment.fingerprint
                    )
                }
            } catch {
                Log.report(error) // one unreadable photo must not end the run
                return []
            }
        }
    }
}
