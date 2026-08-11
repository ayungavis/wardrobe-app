import DesignSystem
import SwiftUI

/// Curated emoji sticker picker (PRD FR-019 — small sticker set).
struct StickerPickerSheet: View {
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

/// A committed sticker on the canvas — drag to move, pinch to resize.
struct CommittedStickerView: View {
    let item: StickerItem
    let canvasSize: CGSize
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onDragActive: (Bool) -> Void
    let onManipulationEnd: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var scaleStartValue: CGFloat?

    var body: some View {
        StickerLabel(item: item, fontSize: TextRendering.stickerFontSize(for: item, in: canvasSize))
            .position(
                x: item.position.x * canvasSize.width,
                y: item.position.y * canvasSize.height
            )
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard canvasSize != .zero else { return }
                let start = dragStartPosition ?? item.position
                if dragStartPosition == nil {
                    onDragActive(true)
                }
                dragStartPosition = start
                onMove(CGPoint(
                    x: start.x + value.translation.width / canvasSize.width,
                    y: start.y + value.translation.height / canvasSize.height
                ))
            }
            .onEnded { _ in
                dragStartPosition = nil
                onDragActive(false)
                onManipulationEnd()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = scaleStartValue ?? item.scale
                scaleStartValue = start
                onScale(start * value.magnification)
            }
            .onEnded { _ in
                scaleStartValue = nil
                onManipulationEnd()
            }
    }
}
