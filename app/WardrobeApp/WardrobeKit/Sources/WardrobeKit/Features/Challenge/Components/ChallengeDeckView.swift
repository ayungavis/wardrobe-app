import SwiftUI
#if os(iOS)
    import UIKit
#endif

struct ChallengeDeckView: View {
    let cards: [ChallengeCard]
    let onAccept: (ChallengeCard) -> Void

    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var bringBackOffset: CGFloat = 0
    @State private var lastHapticTickOffset: CGFloat = 0

    private let parkedOffsetX: CGFloat = -300
    private let parkedOffsetY: CGFloat = -100
    private let swipeThreshold: CGFloat = 120
    private let hapticStepDistance: CGFloat = 12
    
    private static let freestyleCard = ChallengeCard(id: UUID(), prompt: "Freestyle")
    
    private var isDeckCleared: Bool {
            currentIndex >= cards.count
        }
    
    var body: some View {
        ZStack {
            FreestyleOutfitView(
                titleKey:"challenge.freestyle.title",
                messageKey: "challenge.freestyle.text",
                buttonKey: "challenge.accept",
                onAccept: { onAccept(Self.freestyleCard) }
            )
            .aspectRatio(346 / 617, contentMode: .fit)
            .zIndex(-Double(cards.count) - 1)
            .allowsHitTesting(isDeckCleared)
            
            ForEach(cards.indices, id: \.self) { index in
                cardView(for: index)
            }
        }
    }

    @ViewBuilder
    private func cardView(for index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isMostRecentlyParked = index == currentIndex - 1
        let isParked = index < currentIndex

        ChallengeCardView(
            card: cards[index],
            onAccept: { onAccept(cards[index]) }
        )
        .rotationEffect(rotation(for: index))
        .offset(
            x: isCurrent ? dragOffset : (isMostRecentlyParked ? parkedOffsetX + bringBackOffset : (isParked ? parkedOffsetX : 0)),
            y: isParked ? parkedOffsetY : 0
        )
        .zIndex(
            isParked ? Double(100 + index) :
                isCurrent ? (dragOffset < 0 ? 200.0 : 50.0) :
                Double(-index)
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
                tickIfNeeded(currentOffset: dragOffset)
                if dragOffset == 0 {
                    Self.prepareHaptic()   // new — primes it right as the drag starts
                }
            }
            .onEnded { value in
                lastHapticTickOffset = 0
                if value.translation.width < -swipeThreshold {
                    Self.playImpactHaptic()
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
                bringBackOffset = max(0, value.translation.width)
                tickIfNeeded(currentOffset: bringBackOffset)
            }
            .onEnded { value in
                lastHapticTickOffset = 0
                if value.translation.width > swipeThreshold / 2 {
                    Self.playImpactHaptic()
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
    private static let hapticGenerator: UIImpactFeedbackGenerator = {
        #if os(iOS)
            UIImpactFeedbackGenerator(style: .light)
        #endif
    }()

    private static func prepareHaptic() {
        #if os(iOS)
            hapticGenerator.prepare()
        #endif
    }
    private static func playHaptic() {
            #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            #endif
        }
    private func tickIfNeeded(currentOffset: CGFloat) {
            guard abs(currentOffset - lastHapticTickOffset) >= hapticStepDistance else { return }
            lastHapticTickOffset = currentOffset
            Self.playSelectionHaptic()
        }

        private static let selectionGenerator: UISelectionFeedbackGenerator = {
            #if os(iOS)
                UISelectionFeedbackGenerator()
            #endif
        }()

        private static let impactGenerator: UIImpactFeedbackGenerator = {
            #if os(iOS)
                UIImpactFeedbackGenerator(style: .light)
            #endif
        }()

        private static func playSelectionHaptic() {
            #if os(iOS)
                selectionGenerator.selectionChanged()
            #endif
        }

        private static func playImpactHaptic() {
            #if os(iOS)
                impactGenerator.impactOccurred()
            #endif
        }
}

#Preview {
    ChallengeDeckView(
        cards: [
            ChallengeCard(id: UUID(), prompt: "Wear something you haven't worn in a month"),
            ChallengeCard(id: UUID(), prompt: "Mix two patterns you'd normally avoid"),
            ChallengeCard(id: UUID(), prompt: "Style your comfiest piece to look put-together"),
            ChallengeCard(id: UUID(), prompt: "Try an accessory you never reach for"),
        ],
        onAccept: { _ in }
    )
}
