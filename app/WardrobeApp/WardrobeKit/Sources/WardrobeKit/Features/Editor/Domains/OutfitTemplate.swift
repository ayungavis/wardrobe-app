import SwiftUI

public enum OutfitTemplate: String, CaseIterable, Identifiable, Sendable {
    case lookbook
    case blisterGreen
    case blisterCream

    public var id: String {
        rawValue
    }

    var assetName: String {
        switch self {
        case .lookbook: "TemplateLookbook"
        case .blisterGreen: "TemplateBlisterGreen"
        case .blisterCream: "TemplateBlisterCream"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lookbook: "editor.template.lookbook"
        case .blisterGreen: "editor.template.blisterGreen"
        case .blisterCream: "editor.template.blisterCream"
        }
    }
}
