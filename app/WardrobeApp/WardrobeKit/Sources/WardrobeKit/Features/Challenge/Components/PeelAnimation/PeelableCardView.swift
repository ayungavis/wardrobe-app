//
//  PeelableCardView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 14/08/26.
//


import SwiftUI

struct PeelableCardView<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    
    let content: Content
    var onPeeledAway: (() -> Void)?
    
    @State private var coordinator = CardPeelCoordinator()
    @State private var renderedImage: UIImage?
    @State private var isAnimating = false
    
    init(onPeeledAway: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onPeeledAway = onPeeledAway
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            if let renderedImage {
                CardPeelRepresentable(image: renderedImage, coordinator: coordinator)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            } else {
                content // shown briefly while the snapshot renders
            }
        }
        .task { await renderImage() }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimating else { return }
                let upward = max(0, -value.translation.height)
                coordinator.view?.setFraction(min(1, upward / 300), reverse: false) // 300 = drag distance to fully peel, tune to taste
            }
            .onEnded { _ in
                guard !isAnimating else { return }
                let current = coordinator.view?.fraction ?? 0
                isAnimating = true
                if current > 0.35 {
                    coordinator.view?.animate(to: 1, reverse: false, duration: 0.35) {
                        isAnimating = false
                        onPeeledAway?()
                    }
                } else {
                    coordinator.view?.animate(to: 0, reverse: true, duration: 0.3) {
                        isAnimating = false
                    }
                }
            }
    }
    
    @MainActor
    private func renderImage() async {
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        renderedImage = renderer.uiImage
    }
}
