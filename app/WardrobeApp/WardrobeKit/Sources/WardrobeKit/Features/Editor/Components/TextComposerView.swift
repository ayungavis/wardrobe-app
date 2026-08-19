import CoreGraphics
import DesignSystem
import SwiftUI

struct TextComposerView: View {
    let working: TextDraft
    let isExisting: Bool
    let canvasSize: CGSize
    let onUpdate: (TextDraft) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    @FocusState private var isFocused: Bool
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

    private var fontSize: CGFloat {
        TextRendering.baseFontSize(in: canvasSize) * working.transform.scale
    }

    var body: some View {
        ZStack {
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
        // The X was the only way out, and §19 requires a modal to stay
        // dismissable. An escape must not commit, so it is the cancel path.
        .accessibilityAction(.escape, onCancel)
    }

    // MARK: The live text

    private var livePreview: some View {
        BoundedTextWidthLayout(minimumWidth: 44, maximumWidth: 310) {
            ZStack(alignment: working.content.alignmentStyle.frameAlignment) {
                preview
                field
            }

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
            .onSubmit(onDone)
            .accessibilityLabel(Text("editor.text.placeholder", bundle: .module))
            .accessibilityIdentifier("editor.text.field")
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()

            if isExisting {
                Button(role: .destructive) {
                    EditorHaptics.removed.play()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(AppColor.mediaBackground.opacity(0.66), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("editor.text.delete", bundle: .module))
                .accessibilityIdentifier("editor.text.delete")
            }

            Button {
                EditorHaptics.commit.play()
                onDone()
            } label: {
                Text("common.done", bundle: .module)
                    .font(AppFont.body.weight(.bold))
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 42)
                    .background(AppColor.mediaBackground.opacity(0.66), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.text.done")
        }
        .foregroundStyle(AppColor.onMedia)
    }

    private var sizeSlider: some View {
        GeometryReader { proxy in
            let topInset = topBarHeight + Spacing.sm
            let bottomInset = styleBarHeight + Spacing.md
            let available = max(proxy.size.height - topInset - bottomInset, 0)

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
    func sentenceCapitalized() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.sentences)
        #else
            self
        #endif
    }
}
