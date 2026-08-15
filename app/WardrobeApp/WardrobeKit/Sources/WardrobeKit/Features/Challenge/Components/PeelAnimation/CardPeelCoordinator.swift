//
//  CardPeelCoordinator.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 14/08/26.
//


import SwiftUI

final class CardPeelCoordinator {
    weak var view: CardPeelView?
}

struct CardPeelRepresentable: UIViewRepresentable {
    var image: UIImage?
    let coordinator: CardPeelCoordinator

    func makeUIView(context: Context) -> CardPeelView {
        let view = CardPeelView()
        coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: CardPeelView, context: Context) {
        uiView.contentImage = image
        uiView.shadowContentImage = image
    }
}