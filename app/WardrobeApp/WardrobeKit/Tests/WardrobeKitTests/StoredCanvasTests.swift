import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// What people already have on their phones has to keep opening, and history
/// has to survive a shape change. Both are one-way doors, so they are tested
/// against the stored bytes rather than against the types.
struct StoredCanvasTests {
    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Reading the pre-canvas shape

    /// A challenge stored before the layered canvas keeps its crop, its texts
    /// and its stickers — and their ids, so a layer is still the same layer.
    @Test func anActiveChallengeStoredAsAFlatDraftStillOpens() throws {
        let textID = UUID()
        let legacy = Data("""
        {
          "card": { "id": "\(UUID.v7())", "prompt": "Wear red." },
          "acceptedAt": 1000,
          "photoID": "\(id("photo-1").uuidString)",
          "draft": {
            "crop": { "rect": [[0.1, 0.2], [0.6, 0.45]] },
            "texts": [{
              "id": "\(textID.uuidString)", "content": "OOTD",
              "position": [0.25, 0.75], "scale": 1.8
            }],
            "stickers": []
          }
        }
        """.utf8)

        let challenge = try JSONDecoder().decode(ActiveChallenge.self, from: legacy)

        #expect(challenge.photoID == id("photo-1"))
        #expect(challenge.document.firstPhotoCrop?.rect.width == 0.6)
        #expect(challenge.document.textContents == ["OOTD"])
        #expect(challenge.document.layers.contains { $0.id == textID })
    }

    @Test func aCompletedChallengeStoredAsAFlatDraftStillRenders() throws {
        let legacy = Data("""
        {
          "id": "\(UUID.v7())",
          "card": { "id": "\(UUID.v7())", "prompt": "Wear red." },
          "photoID": "\(id("photo-1").uuidString)",
          "completedAt": 2000,
          "draft": { "texts": [], "stickers": [{
            "id": "\(UUID.v7())", "emoji": "✨", "position": [0.9, 0.1], "scale": 2
          }] }
        }
        """.utf8)

        let completion = try JSONDecoder().decode(CompletedChallenge.self, from: legacy)

        #expect(completion.document.stickerEmojis == ["✨"])
        #expect(completion.document.stickerItems.first?.scale == 2)
    }

    /// History renders the composition, so the file holding it has to survive a
    /// round trip — and a completion written before previews existed has to
    /// keep decoding, because history is never migrated in place.
    @Test func previewFileRoundTripsAndIsOptionalOnOlderRecords() throws {
        var completion = CompletedChallenge(
            card: ChallengeCard(prompt: "x"), photoID: id("photo-1"),
            document: .fixture(), completedAt: Date(timeIntervalSince1970: 1000)
        )
        completion.previewFile = "preview-1.jpg"

        let encoded = try JSONEncoder().encode(completion)
        #expect(try JSONDecoder().decode(CompletedChallenge.self, from: encoded).previewFile == "preview-1.jpg")

        let withoutKey = Data("""
        {
          "id": "\(UUID.v7())",
          "card": { "id": "\(UUID.v7())", "prompt": "Wear red." },
          "photoID": "\(id("photo-1").uuidString)",
          "completedAt": 2000,
          "draft": { "texts": [], "stickers": [] }
        }
        """.utf8)

        #expect(try JSONDecoder().decode(CompletedChallenge.self, from: withoutKey).previewFile == nil)
    }

    /// Once read, it is written back in the new shape — the old key is a read
    /// path, not a format we keep producing.
    @Test func aMigratedChallengeIsRewrittenAsADocument() throws {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = id("photo-1")
        challenge.document = .fixture(texts: [TextItem(content: "hi")])

        let encoded = try JSONEncoder().encode(challenge)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(json["document"] != nil)
        #expect(json["draft"] == nil)
        #expect(try JSONDecoder().decode(ActiveChallenge.self, from: encoded) == challenge)
    }

    // MARK: History survives what it cannot read

    /// Decoding the array in one go used to mean a single unreadable entry
    /// erased the whole history — and the next append wrote the empty array
    /// back over it.
    @Test func oneUnreadableCompletionDoesNotTakeTheRestWithIt() throws {
        let defaults = try makeDefaults("StoredCanvasTests.history")
        let good = CompletedChallenge(
            card: ChallengeCard(prompt: "x"), photoID: id("photo-1"),
            document: .fixture(), completedAt: Date(timeIntervalSince1970: 1000)
        )
        let encodedGood = try JSONSerialization.jsonObject(with: JSONEncoder().encode(good))
        let mixed = try JSONSerialization.data(withJSONObject: [
            encodedGood, ["nonsense": true], encodedGood,
        ])
        defaults.set(mixed, forKey: "completedChallenges")

        let repository = UserDefaultsCompletedChallengeRepository(defaults: defaults)

        #expect(repository.load().count == 2)
    }

    @Test func appendingAfterAnUnreadableEntryKeepsTheReadableOnes() throws {
        let defaults = try makeDefaults("StoredCanvasTests.append")
        let old = CompletedChallenge(
            card: ChallengeCard(prompt: "old"), photoID: id("photo-1"),
            document: .fixture(), completedAt: Date(timeIntervalSince1970: 1000)
        )
        let encodedOld = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        let mixed = try JSONSerialization.data(withJSONObject: [["nonsense": true], encodedOld])
        defaults.set(mixed, forKey: "completedChallenges")

        let repository = UserDefaultsCompletedChallengeRepository(defaults: defaults)
        repository.append(CompletedChallenge(
            card: ChallengeCard(prompt: "new"), photoID: id("photo-2"),
            document: .fixture(), completedAt: Date(timeIntervalSince1970: 200_000)
        ))

        #expect(repository.load().map(\.card.prompt) == ["old", "new"])
    }
}
