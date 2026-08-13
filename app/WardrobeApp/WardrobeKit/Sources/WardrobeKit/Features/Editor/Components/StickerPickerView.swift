import DesignSystem
import SwiftUI

/// Curated emoji sticker picker (PRD FR-019 — small sticker set).
struct StickerPickerView: View {
    let onPick: (String) -> Void

    // ponytail: hardcoded curated set; move to a remote/config source when
    // the sticker library needs to grow.
    private static let emojis = [
        "🔥", "❤️", "😍", "✨", "💫", "⭐️", "🌈", "☀️",
        "😎", "🤩", "💯", "🙌", "👌", "✌️", "🫶", "🎉",
        "💃", "🕺", "👗", "👖", "👟", "🧢", "🕶️", "👜",
        "🧥", "👒", "🌸", "🍂", "❄️", "💅",
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.lg) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                    } label: {
                        Text(verbatim: emoji)
                            .font(.system(size: 40))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text(verbatim: emoji))
                }
            }
            .padding(Spacing.xl)
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}
