import DesignSystem
import SwiftUI

/// A committed text item on the canvas — story-style direct manipulation:
/// tap to edit content, drag to move, pinch to resize.
struct CommittedTextView: View {
    let item: TextItem
    let canvasSize: CGSize
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onDragActive: (Bool) -> Void
    let onManipulationEnd: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var scaleStartValue: CGFloat?

    var body: some View {
        TextItemLabel(item: item, fontSize: TextRendering.fontSize(for: item, in: canvasSize))
            .position(
                x: item.position.x * canvasSize.width,
                y: item.position.y * canvasSize.height
            )
            .onTapGesture(perform: onTap)
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

/// Story-style text composer: dimmed backdrop, centered field above the
/// keyboard, color palette + background toggle, Done in the corner.
struct TextComposerOverlay: View {
    let working: TextItem
    let isExisting: Bool
    let onUpdate: (TextItem) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            AppColor.mediaBackground.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDone)

            VStack {
                composerBar

                Spacer()

                TextField(
                    String(localized: "editor.text.placeholder", bundle: .module),
                    text: Binding(
                        get: { working.content },
                        set: { newValue in
                            var updated = working
                            updated.content = newValue
                            onUpdate(updated)
                        }
                    ),
                    axis: .vertical
                )
                .font(.system(size: 34 * working.scale, weight: .bold))
                .foregroundStyle(working.hasBackground ? working.textColor.contrastText : working.textColor.color)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background {
                    if working.hasBackground {
                        Capsule().fill(working.textColor.color)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()

                StylingBar(working: working, onUpdate: onUpdate)
            }
        }
        .task { isFocused = true }
    }

    private var composerBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("common.cancel", bundle: .module)
                    .frame(minHeight: 44)
            }

            Spacer()

            if isExisting {
                // Accessible deletion path — drag-to-trash needs a drag.
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("challenge.abandon.confirm.action", bundle: .module))
            }

            Button(action: onDone) {
                Text("common.done", bundle: .module)
                    .bold()
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(AppColor.onMedia)
        .padding(.horizontal, Spacing.lg)
    }
}

/// Color palette dots + background-pill toggle (Instagram-style).
private struct StylingBar: View {
    let working: TextItem
    let onUpdate: (TextItem) -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button {
                var updated = working
                updated.hasBackground.toggle()
                onUpdate(updated)
            } label: {
                Image(systemName: working.hasBackground ? "a.square.fill" : "a.square")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColor.onMedia)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("editor.text.background", bundle: .module))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(TextColor.allCases, id: \.rawValue) { paletteColor in
                        Button {
                            var updated = working
                            updated.colorName = paletteColor.rawValue
                            onUpdate(updated)
                        } label: {
                            Circle()
                                .fill(paletteColor.color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle().strokeBorder(
                                        AppColor.onMedia,
                                        lineWidth: working.colorName == paletteColor.rawValue ? 3 : 1
                                    )
                                }
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text(verbatim: paletteColor.rawValue))
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }
}
