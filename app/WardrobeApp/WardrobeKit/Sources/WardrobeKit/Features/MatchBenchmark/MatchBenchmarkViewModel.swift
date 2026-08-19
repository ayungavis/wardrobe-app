import Foundation
import Observation

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
    private var nextGroupIndex = 0

    private let scanner: GarmentScanService
    private let thumbnails: GarmentThumbnailRepository

    init(scanner: GarmentScanService, thumbnails: GarmentThumbnailRepository) {
        self.scanner = scanner
        self.thumbnails = thumbnails
    }

    func add(photos: [Data]) {
        guard !photos.isEmpty else { return }
        let index = nextGroupIndex
        nextGroupIndex += 1
        isScanning = true
        report = nil

        Task {
            defer { isScanning = false }
            let scanned = await scan(photos, groupIndex: index)
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

    private func scan(_ photos: [Data], groupIndex: Int) async -> [BenchmarkSample] {
        var samples: [BenchmarkSample] = []
        for photo in photos {
            do {
                for garment in try await scanner.scan(photo: photo) {
                    try? thumbnails.delete(file: garment.cutoutFile)
                    samples.append(BenchmarkSample(
                        id: garment.id,
                        groupIndex: groupIndex,
                        category: garment.category,
                        fingerprint: garment.fingerprint
                    ))
                }
            } catch {
                Log.report(error) // one unreadable photo must not end the run
            }
        }
        return samples
    }
}
