import Foundation

enum WardrobeSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func results(in items: [WardrobeItem], matching query: String) -> [WardrobeItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }

        return items.filter { item in
            terms.allSatisfy { term in
                item.name.range(of: term, options: options) != nil
                    || item.description.range(of: term, options: options) != nil
            }
        }
    }
}
