import Foundation
import Testing
@testable import WardrobeKit

/// Invariants of the string catalogue itself, checked against the file because
/// SwiftPM copies `.xcstrings` uncompiled — under `swift test` nothing
/// localizes, so runtime behaviour cannot be observed here.
struct LocalizationCatalogueTests {
    private func catalogueStrings() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])
    }

    /// A key ending in `.%@` can only be born one way: an interpolated literal
    /// passed to `String.LocalizationValue`, which builds a *format* instead of
    /// a key. The lookup then misses and the raw key lands on screen.
    ///
    /// The runtime forms are indistinguishable in this test environment, but
    /// the mistake leaves this fingerprint in the catalogue — so this is the
    /// place it can be caught. `LocalizedKey.resolve` is what avoids it.
    @Test func noKeyIsAFormatBuiltFromARuntimeValue() throws {
        let offenders = try catalogueStrings().keys.filter { $0.hasSuffix(".%@") }

        #expect(
            offenders.isEmpty,
            "\(offenders) came from interpolating into String.LocalizationValue — use LocalizedKey.resolve"
        )
    }

    /// Deliberate formats are a different thing entirely and stay welcome.
    @Test func countedFormatsAreUntouchedByThatRule() throws {
        let strings = try catalogueStrings()

        #expect(strings["editor.review.detected %lld"] != nil)
        #expect(strings["editor.text.counter %lld %lld"] != nil)
    }

    /// Every language the app advertises must actually be in the catalogue.
    @Test func everyTranslatedKeyCarriesBothLanguages() throws {
        for (key, value) in try catalogueStrings() {
            guard let localizations = (value as? [String: Any])?["localizations"] as? [String: Any],
                  !localizations.isEmpty
            else {
                continue // a key with no localizations at all is the extractor's, not ours
            }

            for language in ["en", "id"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                #expect((unit?["value"] as? String)?.isEmpty == false, "\(key) has no \(language) value")
            }
        }
    }
}
