import Foundation
import Testing
@testable import WardrobeKit

private let storedByTheOldBuild = """
{
  "id" : "A1B2C3D4-1111-4222-8333-444444444444",
  "schemaVersion" : 2,
  "background" : {
    "photoID" : "B0000000-0000-4000-8000-000000000001"
  },
  "layers" : [
    {
      "id" : "C0000000-0000-4000-8000-000000000002",
      "isLocked" : false,
      "content" : {
        "kind" : "photo",
        "value" : { "photoID" : "D0000000-0000-4000-8000-000000000003" }
      },
      "transform" : { "position" : [0.5, 0.5], "rotationDegrees" : 0, "scale" : 1 }
    }
  ]
}
"""

struct StoredPhotoIdentityTests {
    @Test func aDocumentWrittenBeforeTheChangeStillOpens() throws {
        let document = try JSONDecoder().decode(
            EditorDocument.self, from: Data(storedByTheOldBuild.utf8)
        )

        #expect(
            document.background.photoID
                == UUID(uuidString: "B0000000-0000-4000-8000-000000000001")
        )
        #expect(document.layers.count == 1)
        guard case let .photo(content) = document.layers[0].content else {
            Issue.record("the photo layer has to survive the decode")
            return
        }
        #expect(content.photoID == UUID(uuidString: "D0000000-0000-4000-8000-000000000003"))
    }

    /// The claim that carries the decision not to bump `currentSchemaVersion`:
    /// the bytes on disk do not change shape.
    @Test func reEncodingProducesTheSameStoredShape() throws {
        let decoded = try JSONDecoder().decode(
            EditorDocument.self, from: Data(storedByTheOldBuild.utf8)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let round = try encoder.encode(decoded)

        let original = try JSONSerialization.jsonObject(with: Data(storedByTheOldBuild.utf8))
        let rewritten = try JSONSerialization.jsonObject(with: round)
        #expect(
            NSDictionary(dictionary: original as? [String: Any] ?? [:])
                == NSDictionary(dictionary: rewritten as? [String: Any] ?? [:]),
            "a changed shape would mean currentSchemaVersion has to move"
        )
        #expect(decoded.schemaVersion == 2)
    }

    @Test func aStoredIdentityThatIsNotAUUIDIsRefusedRatherThanLost() {
        let corrupt = storedByTheOldBuild.replacingOccurrences(
            of: "\"D0000000-0000-4000-8000-000000000003\"", with: "\"not-an-id\""
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EditorDocument.self, from: Data(corrupt.utf8))
        }
    }

    @Test func newlyMintedPhotoIdentitiesCarryTheMomentTheyWereSaved() throws {
        let repository = FilePhotoRepository(directory: temporaryDirectory())

        let first = try repository.saveOriginal(Data([0xFF, 0xD8]))
        let second = try repository.saveOriginal(Data([0xFF, 0xD8]))

        #expect(first.uuidString.split(separator: "-")[2].first == "7")
        #expect(second.uuidString.split(separator: "-")[2].first == "7")
        #expect(first != second)

        let stamp = try #require(mintedAt(first))
        #expect(
            abs(stamp.timeIntervalSinceNow) < 5,
            "the leading 48 bits are a millisecond clock, which is what makes ids sort by time"
        )
    }

    @Test func savingThenLoadingReturnsTheSameBytes() throws {
        let repository = FilePhotoRepository(directory: temporaryDirectory())
        let bytes = Data([0xFF, 0xD8, 0x01, 0x02, 0x03])

        let id = try repository.saveOriginal(bytes)

        #expect(try repository.loadOriginal(id: id) == bytes)
    }
}

private func temporaryDirectory() -> URL {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func mintedAt(_ identity: UUID) -> Date? {
    let hex = identity.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
    guard let milliseconds = UInt64(hex, radix: 16) else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
}
