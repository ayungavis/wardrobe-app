import SwiftUI

struct CurlingCardView<Content: View>: View {
    let content: Content
    var onCurledAway: (() -> Void)?

    @State private var dragProgress: CGFloat = 0
    @State private var isAnimatingAway = false

    private let sliceCount = 24

    init(onCurledAway: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onCurledAway = onCurledAway
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let sliceHeight = height / CGFloat(sliceCount)

            ZStack(alignment: .top) {
                ForEach(0 ..< sliceCount, id: \.self) { slice in
                    content
                        .frame(width: geo.size.width, height: height)
                        .mask(
                            Rectangle()
                                .frame(width: geo.size.width, height: sliceHeight)
                                .offset(y: CGFloat(slice) * sliceHeight)
                        )
                        .rotation3DEffect(
                            curlAngle(forSlice: slice),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .top,
                            anchorZ: 0,
                            perspective: 0.35
                        )
                        .offset(y: curlOffset(forSlice: slice, sliceHeight: sliceHeight))
                        .opacity(curlOpacity(forSlice: slice))
                        .shadow(color: .black.opacity(0.15 * dragProgress), radius: 3, y: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isAnimatingAway else { return }
                        let upward = max(0, -value.translation.height)
                        dragProgress = min(1.0, upward / height)
                    }
                    .onEnded { _ in
                        guard !isAnimatingAway else { return }
                        if dragProgress > 0.35 {
                            isAnimatingAway = true
                            withAnimation(.easeIn(duration: 0.4)) {
                                dragProgress = 1.0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onCurledAway?()
                            }
                        } else {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                dragProgress = 0
                            }
                        }
                    }
            )
        }
    }

    private func localProgress(forSlice slice: Int) -> CGFloat {
        let sliceFraction = CGFloat(slice) / CGFloat(sliceCount)
        let adjusted = (dragProgress - sliceFraction * 0.6) / 0.4
        return min(max(adjusted, 0), 1)
    }

    private func curlAngle(forSlice slice: Int) -> Angle {
        .degrees(Double(localProgress(forSlice: slice)) * 180)
    }

    private func curlOffset(forSlice slice: Int, sliceHeight: CGFloat) -> CGFloat {
        let progress = localProgress(forSlice: slice)
        return -progress * sliceHeight * 0.5
    }

    private func curlOpacity(forSlice slice: Int) -> Double {
        let progress = localProgress(forSlice: slice)
        return progress > 0.85 ? Double(1 - (progress - 0.85) / 0.15) : 1
    }
}
