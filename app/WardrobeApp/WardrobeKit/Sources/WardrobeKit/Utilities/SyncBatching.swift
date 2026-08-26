import Foundation

enum SyncBatching {
    static let maxMutations = 100
    static let maxBytes = 1_048_576

    static func batches(from mutations: [MutationRequestDTO]) throws -> [[MutationRequestDTO]] {
        guard !mutations.isEmpty else { return [] }

        let encoder = JSONEncoder.api
        let sized = try mutations.map { try ($0, encoder.encode($0).count) }

        var batches: [[MutationRequestDTO]] = []
        var current: [MutationRequestDTO] = []
        var bytes = envelopeBytes

        for (mutation, size) in sized {
            let separator = current.isEmpty ? 0 : 1
            let wouldBe = bytes + separator + size
            if !current.isEmpty, current.count >= maxMutations || wouldBe > maxBytes {
                batches.append(current)
                current = []
                bytes = envelopeBytes
            }
            // ponytail: a mutation that alone exceeds maxBytes still ships alone.
            // The server answers 413 and the outbox marks it failed, which is
            // FR-057's "no mutation is silently discarded" — dropping it here
            // would be the one outcome the requirement forbids.
            current.append(mutation)
            bytes += (current.count == 1 ? 0 : 1) + size
        }
        batches.append(current)
        return batches
    }

    static func failedIdentifiers(in response: PostSyncResponseDTO) -> [UUID] {
        response.results.compactMap { result in
            switch result.outcome {
            case .applied: nil
            case .failed: result.id
            }
        }
    }

    private static let envelopeBytes = "{\"mutations\":[]}".utf8.count
}
