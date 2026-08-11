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
    let onManipulationEnd: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var scaleStartValue: CGFloat?

    var body: some View {
        Text(item.content)
            .font(.system(size: TextRendering.fontSize(for: item, in: canvasSize), weight: .bold))
            .foregroundStyle(AppColor.onMedia)
            .shadow(color: AppColor.mediaBackground.opacity(0.4), radius: 2)
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
                dragStartPosition = start
                onMove(CGPoint(
                    x: start.x + value.translation.width / canvasSize.width,
                    y: start.y + value.translation.height / canvasSize.height
                ))
            }
            .onEnded { _ in
                dragStartPosition = nil
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
/// keyboard, Done in the corner. Tapping the backdrop also commits.
struct TextComposerOverlay: View {
    let working: TextItem
    let isExisting: Bool
    let onContentChange: (String) -> Void
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
                HStack {
                    Button(action: onCancel) {
                        Text("common.cancel", bundle: .module)
                            .frame(minHeight: 44)
                    }

                    Spacer()

                    if isExisting {
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

                Spacer()

                TextField(
                    String(localized: "editor.text.placeholder", bundle: .module),
                    text: Binding(get: { working.content }, set: onContentChange),
                    axis: .vertical
                )
                .font(.system(size: 34 * working.scale, weight: .bold))
                .foregroundStyle(AppColor.onMedia)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(.horizontal, Spacing.xl)

                Spacer()
            }
        }
        .task { isFocused = true }
    }
}
