//
//  CurlingCardView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 14/08/26.
//


import SwiftUI

struct CurlingCardView<Content: View>: View {
    let content: Content
    var onCurledAway: (() -> Void)?

    @State private var dragProgress: CGFloat = 0 // 0 = flat, 1 = fully curled away
    @State private var isAnimatingAway = false

    private let sliceCount = 24 // more slices = smoother curl, more render cost

    init(onCurledAway: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onCurledAway = onCurledAway
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let sliceHeight = height / CGFloat(sliceCount)

            ZStack(alignment: .top) {
                ForEach(0..<sliceCount, id: \.self) { i in
                    content
                        .frame(width: geo.size.width, height: height)
                        .mask(
                            Rectangle()
                                .frame(width: geo.size.width, height: sliceHeight)
                                .offset(y: CGFloat(i) * sliceHeight)
                        )
                        .rotation3DEffect(
                            curlAngle(forSlice: i),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .top,
                            anchorZ: 0,
                            perspective: 0.35
                        )
                        .offset(y: curlOffset(forSlice: i, sliceHeight: sliceHeight))
                        .opacity(curlOpacity(forSlice: i))
                        .shadow(color: .black.opacity(0.15 * dragProgress), radius: 3, y: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isAnimatingAway else { return }
                        // Dragging UP peels the card away, from the top down
                        let upward = max(0, -value.translation.height)
                        dragProgress = min(1.0, upward / height)
                    }
                    .onEnded { value in
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

    // Each slice's own "local progress" — slices near the top curl first, bottom slices lag behind
    private func localProgress(forSlice i: Int) -> CGFloat {
        let sliceFraction = CGFloat(i) / CGFloat(sliceCount) // 0 (top) to 1 (bottom)
        // top slices reach full curl before bottom slices even start — creates the rolling curl look
        let adjusted = (dragProgress - sliceFraction * 0.6) / 0.4
        return min(max(adjusted, 0), 1)
    }

    private func curlAngle(forSlice i: Int) -> Angle {
        .degrees(Double(localProgress(forSlice: i)) * 180)
    }

    private func curlOffset(forSlice i: Int, sliceHeight: CGFloat) -> CGFloat {
        let progress = localProgress(forSlice: i)
        return -progress * sliceHeight * 0.5 // slight lift as it curls
    }

    private func curlOpacity(forSlice i: Int) -> Double {
        let progress = localProgress(forSlice: i)
        // fades out near the very end of its own curl, like the paper rolling out of view
        return progress > 0.85 ? Double(1 - (progress - 0.85) / 0.15) : 1
    }
}
