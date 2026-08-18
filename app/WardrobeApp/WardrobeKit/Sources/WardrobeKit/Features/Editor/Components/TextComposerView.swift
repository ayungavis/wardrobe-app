import CoreGraphics
import DesignSystem
import SwiftUI

/// Full-screen text editing: the words render live in their own font, colour,
/// alignment, and pill while you type.
///
/// The trick is a `TextField` whose own glyphs are transparent, stacked over a
/// `TextItemLabelView` showing the same string. The field contributes only the
/// caret and selection; everything visible is the real layer renderer — the
/// same one the canvas and the exporter use, at the size the canvas will give
/// it. So the preview is not a likeness of the result, it *is* the result.
struct TextComposerView: View {
    let working: TextDraft
    let isExisting: Bool
    /// The live canvas size, so the preview is drawn at the size this text will
    /// actually be once it lands.
    let canvasSize: CGSize
    let onUpdate: (TextDraft) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    @FocusState private var isFocused: Bool
    /// Measured so the size slider can be given the room that is actually left
    /// between them, instead of guessing and landing under the panel.
    @State private var topBarHeight: CGFloat = 66
    @State private var styleBarHeight: CGFloat = 170

    private var content: Binding<TextContent> {
        Binding(
            get: { working.content },
            set: { updated in
                var draft = working
                draft.content = updated
                onUpdate(draft)
            }
        )
    }

    private var scale: Binding<CGFloat> {
        Binding(
            get: { working.transform.scale },
            set: { updated in
                var draft = working
                draft.transform.scale = updated
                onUpdate(draft)
            }
        )
    }

    /// No fallback for an unmeasured canvas on purpose. The canvas is laid out
    /// long before any tool can open, and a plausible-looking stand-in is what
    /// let a real size mismatch hide here once already.
    private var fontSize: CGFloat {
        TextRendering.baseFontSize(in: canvasSize) * working.transform.scale
    }

    var body: some View {
        ZStack {
            // Dimmed, not opaque: the canvas behind is the thing this text has
            // to look right against, so it stays visible while you type.
            AppColor.mediaBackground.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }

            livePreview

            sizeSlider

            VStack(spacing: 0) {
                topBar
                    .padding(Spacing.md)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        topBarHeight = newHeight
                    }

                Spacer(minLength: Spacing.md)

                TextStyleBarView(content: content)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        styleBarHeight = newHeight
                    }
            }
        }
        .task { isFocused = true }
    }

    // MARK: The live text

    private var livePreview: some View {
        BoundedTextWidthLayout(minimumWidth: 44, maximumWidth: 310) {
            ZStack(alignment: working.content.alignmentStyle.frameAlignment) {
                preview
                field
            }

            // Measured, never drawn. It must show exactly what the visible copy
            // shows — measuring the real content while drawing the placeholder
            // is what squeezed an empty draft into the 44pt minimum and left
            // "Type something…" as "T…".
            TextItemLabelView(item: previewContent, fontSize: fontSize)
                .lineLimit(1 ... 7)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(Spacing.xl)
    }

    private var preview: some View {
        TextItemLabelView(item: previewContent, fontSize: fontSize)
            .lineLimit(1 ... 7)
            .opacity(working.content.content.isEmpty ? 0.36 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// An empty layer shows the placeholder through the very same renderer, so
    /// the prompt already wears the style you are about to type in.
    private var previewContent: TextContent {
        guard working.content.content.isEmpty else { return working.content }
        var placeholder = working.content
        placeholder.content = String(localized: "editor.text.placeholder", bundle: .module)
        return placeholder
    }

    private var field: some View {
        TextField("", text: content.content, axis: .vertical)
            .font(.system(
                size: fontSize,
                weight: working.content.fontStyle.weight,
                design: working.content.fontStyle.design
            ))
            .foregroundStyle(Color.clear)
            .multilineTextAlignment(working.content.alignmentStyle.textAlignment)
            .lineLimit(1 ... 7)
            .textFieldStyle(.plain)
            .tint(AppColor.accent)
            .focused($isFocused)
            .sentenceCapitalized()
            .submitLabel(.done)
            .onSubmit {
                if !working.isBlank {
                    onDone()
                }
            }
            .accessibilityLabel(Text("editor.text.placeholder", bundle: .module))
            .accessibilityIdentifier("editor.text.field")
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(AppColor.mediaBackground.opacity(0.66), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.cancel", bundle: .module))
            .accessibilityIdentifier("editor.text.cancel")

            Spacer()

            // Only for a text that already exists: deleting is otherwise a trip
            // back to the canvas to drag it to the bin.
            if isExisting {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AppColor.mediaBackground.opacity(0.66), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("editor.text.delete", bundle: .module))
                .accessibilityIdentifier("editor.text.delete")
            }

            Button(action: onDone) {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 42)
                    .background(AppColor.mediaBackground.opacity(0.66), in: .capsule)
            }
            .buttonStyle(.plain)
            // Clearing the words is not how a text is deleted, and nothing on
            // screen says it would be — so an empty draft simply cannot commit.
            .disabled(working.isBlank)
            .opacity(working.isBlank ? 0.45 : 1)
            .accessibilityIdentifier("editor.text.done")
        }
        .foregroundStyle(AppColor.onMedia)
    }

    /// Fitted into the gap the chrome leaves rather than centred on the screen,
    /// which is what put its lower half under the style panel.
    private var sizeSlider: some View {
        GeometryReader { proxy in
            let topInset = topBarHeight + Spacing.sm
            let bottomInset = styleBarHeight + Spacing.md
            let available = max(proxy.size.height - topInset - bottomInset, 0)

            // Below this it is too short to aim at; the adjustable action on the
            // slider keeps size reachable without it.
            if available >= 96 {
                let height = min(230, available)
                TextSizeSliderView(scale: scale)
                    .frame(width: 44, height: height)
                    .position(x: Spacing.lg + 22, y: topInset + height / 2)
            }
        }
    }
}

private extension View {
    /// iOS-only; the package also builds for macOS so `swift test` can run
    /// without a simulator.
    func sentenceCapitalized() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.sentences)
        #else
            self
        #endif
    }
}
