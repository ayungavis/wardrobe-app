//
//  ChallengeDeckView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 14/08/26.
//
import SwiftUI

struct ChallengeDeckView: View {
    let cards: [ChallengeCard]
    let onAccept: (ChallengeCard) -> Void

    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0        // drag for the current (front) card
    @State private var bringBackOffset: CGFloat = 0   // drag for the most recently parked card

    private let parkedOffsetX: CGFloat = -300
    private let parkedOffsetY: CGFloat = -100
    private let swipeThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            ForEach(cards.indices, id: \.self) { i in
                cardView(for: i)
            }
        }
    }

    @ViewBuilder
    private func cardView(for i: Int) -> some View {
        let isCurrent = i == currentIndex
        let isMostRecentlyParked = i == currentIndex - 1
        let isParked = i < currentIndex

        ChallengeCardView(
            card: cards[i],
            onAccept: { onAccept(cards[i]) }
        )
        .rotationEffect(rotation(for: i))
        .offset(
            x: isCurrent ? dragOffset : (isMostRecentlyParked ? parkedOffsetX + bringBackOffset : (isParked ? parkedOffsetX : 0)),
            y: isParked ? parkedOffsetY : 0
        )
        //.zIndex(isCurrent ? Double(cards.count + 1) : (isParked ? Double(i + cards.count) : Double(cards.count - i)))
        .zIndex(
            isParked ? Double(100 + i) :
            isCurrent ? (dragOffset < 0 ? 200.0 : 50.0) :
            Double(-i)
        )
        .allowsHitTesting(isCurrent || isMostRecentlyParked)
        .gesture(swipeAwayGesture, including: isCurrent ? .all : .none)
        .gesture(bringBackGesture, including: isMostRecentlyParked ? .all : .none)
    }

    private func rotation(for index: Int) -> Angle {
        let angles: [Double] = [-4, 3, -2, 5, -3, 2, -5, 4]
        return .degrees(angles[index % angles.count])
    }

    private var swipeAwayGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width < -swipeThreshold {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentIndex += 1
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var bringBackGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only respond to rightward drags — pulling the card back toward center
                bringBackOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width > swipeThreshold / 2 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentIndex -= 1
                        bringBackOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        bringBackOffset = 0
                    }
                }
            }
    }
}

#Preview {
    ChallengeDeckView(
        cards: [
            ChallengeCard(id: UUID(), prompt: "Wear something you haven't worn in a month"),
            ChallengeCard(id: UUID(), prompt: "Mix two patterns you'd normally avoid"),
            ChallengeCard(id: UUID(), prompt: "Style your comfiest piece to look put-together"),
            ChallengeCard(id: UUID(), prompt: "Try an accessory you never reach for")
        ],
        onAccept: { _ in }
    )
}
